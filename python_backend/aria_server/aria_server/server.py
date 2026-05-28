from __future__ import annotations

import argparse
import asyncio
import http.server
import json
import socketserver
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from shared.bonjour import BonjourServiceBroadcaster
from shared.protocol_v2 import (
    ALLOWED_CC_CONTROLLERS,
    ControlChangeEvent,
    ErrorResponseV2,
    GenerateRequestV2,
    ResultResponseV2,
    legalize_events,
)

from aria.run import _load_inference_model_mlx
from ariautils.tokenizer import AbsTokenizer
from ariautils.midi import MidiDict
from aria.inference import get_inference_prompt
from aria.inference.sample_mlx import sample_batch


@dataclass(frozen=True)
class ServerConfig:
    host: str
    port: int
    checkpoint: Path


class _Handler(http.server.BaseHTTPRequestHandler):
    server_version = "aria_server/0.0.1"

    def do_GET(self) -> None:  # noqa: N802
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"aria_server running. POST /generate with protocol_version=2.\n")

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/generate":
            self._send_json(404, ErrorResponseV2(message="not_found").model_dump())
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send_json(400, ErrorResponseV2(message="invalid_content_length").model_dump())
            return

        raw = self.rfile.read(max(0, content_length))
        try:
            payload = json.loads(raw.decode("utf-8"))
        except Exception:
            self._send_json(400, ErrorResponseV2(message="invalid_json").model_dump())
            return

        try:
            request = GenerateRequestV2.model_validate(payload)
        except Exception as exc:
            self._send_json(400, ErrorResponseV2(message=f"invalid_request: {exc}").model_dump())
            return

        pipeline = getattr(self.server, "aria_pipeline", None)
        if pipeline is not None:
            pipeline.generate_best_effort(prompt_events=request.events, params=request.params.model_dump())

        # Echo mode (P2-T2): legalize + filter unknown CC, and always include at least one CC64.
        events = legalize_events(request.events)
        defaults: list[ControlChangeEvent] = []
        if not any(isinstance(e, ControlChangeEvent) and e.controller == 64 for e in events):
            defaults.append(ControlChangeEvent(controller=64, value=0, time=0.0))
        if not any(isinstance(e, ControlChangeEvent) and e.controller == 7 for e in events):
            defaults.append(ControlChangeEvent(controller=7, value=100, time=0.0))
        if not any(isinstance(e, ControlChangeEvent) and e.controller == 11 for e in events):
            defaults.append(ControlChangeEvent(controller=11, value=100, time=0.0))

        if defaults:
            events = legalize_events(defaults + events)

        response = ResultResponseV2(events=events, latency_ms=0)
        self._send_json(200, response.model_dump())

    def _send_json(self, status_code: int, obj: dict[str, Any]) -> None:
        body = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:  # noqa: A002
        # Keep the default HTTP server quiet; use explicit prints in main.
        return


def _default_checkpoint_path() -> Path:
    python_backend_dir = Path(__file__).resolve().parents[2]
    return python_backend_dir / "aria" / "hf" / "model-demo.safetensors"


def parse_args(argv: list[str] | None = None) -> ServerConfig:
    parser = argparse.ArgumentParser(prog="aria_server", add_help=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--checkpoint", type=Path, default=_default_checkpoint_path())
    args = parser.parse_args(argv)
    return ServerConfig(host=args.host, port=args.port, checkpoint=args.checkpoint)


def run(config: ServerConfig) -> None:
    service_type = "_lpduet._tcp"
    txt = {"path": "/generate", "protocol_version": "2", "engine": "aria", "engine_impl": "aria"}
    broadcaster = BonjourServiceBroadcaster(
        service_type=service_type,
        instance_name="LonelyPianist Aria",
        port=config.port,
        properties={k.encode("utf-8"): v.encode("utf-8") for k, v in txt.items()},
    )

    stop_event = threading.Event()

    def bonjour_thread_main() -> None:
        async def runner() -> None:
            await broadcaster.start()
            try:
                while stop_event.is_set() is False:
                    await asyncio.sleep(0.25)
            finally:
                await broadcaster.stop()

        asyncio.run(runner())

    print(f"[aria_server] checkpoint={config.checkpoint}", flush=True)
    print(f"[aria_server] listening=http://{config.host}:{config.port}", flush=True)
    print(f"[aria_server] bonjour service_type={service_type} txt={txt}", flush=True)
    print(f"[aria_server] allowed_cc={sorted(ALLOWED_CC_CONTROLLERS)}", flush=True)

    bonjour_thread = threading.Thread(target=bonjour_thread_main, name="bonjour", daemon=True)
    bonjour_thread.start()

    try:
        with socketserver.ThreadingTCPServer((config.host, config.port), _Handler) as httpd:
            httpd.aria_pipeline = AriaPipeline(checkpoint=config.checkpoint)
            httpd.serve_forever(poll_interval=0.2)
    except KeyboardInterrupt:
        pass
    finally:
        stop_event.set()
        bonjour_thread.join(timeout=2)


class AriaPipeline:
    def __init__(self, checkpoint: Path):
        self._checkpoint = checkpoint
        self._lock = threading.Lock()
        self._tokenizer: AbsTokenizer | None = None
        self._model = None
        self._last_prompt: MidiDict | None = None
        self._last_reply: MidiDict | None = None

    def _ensure_loaded(self) -> None:
        if self._model is not None and self._tokenizer is not None:
            return

        python_backend_dir = Path(__file__).resolve().parents[2]
        tokenizer_config = python_backend_dir / "aria" / "demo" / "demo-tokenizer-config.json"
        self._tokenizer = AbsTokenizer(config_path=tokenizer_config)

        if self._checkpoint.exists() is False:
            raise FileNotFoundError(f"checkpoint missing: {self._checkpoint}")

        self._model = _load_inference_model_mlx(str(self._checkpoint), config_name="medium-emb", strict=False)
        print("[aria_server] model loaded", flush=True)

    def generate_best_effort(self, prompt_events: list[Any], params: dict[str, Any]) -> None:
        # P2-T3: best-effort pipeline skeleton; response still echoes events until P2-T4.
        try:
            with self._lock:
                started = time.perf_counter()
                self._ensure_loaded()
                assert self._tokenizer is not None
                assert self._model is not None

                midi_prompt = _events_to_mididict(prompt_events, ticks_per_beat=480, bpm=120)
                self._last_prompt = midi_prompt
                prompt = get_inference_prompt(midi_dict=midi_prompt, tokenizer=self._tokenizer, prompt_len_ms=15_000)

                max_new_tokens = int(params.get("max_tokens", 512))
                temp = 0.98
                min_p = 0.035
                results = sample_batch(
                    model=self._model,
                    tokenizer=self._tokenizer,
                    prompt=prompt,
                    num_variations=1,
                    max_new_tokens=max_new_tokens,
                    temp=temp,
                    force_end=False,
                    min_p=min_p,
                    top_p=None,
                )
                if results:
                    self._last_reply = self._tokenizer.detokenize(results[0])
                elapsed_ms = int(round((time.perf_counter() - started) * 1000))
                print(f"[aria_server] generation done in {elapsed_ms}ms", flush=True)
        except Exception as exc:
            import traceback

            print(f"[aria_server] generate_best_effort failed: {exc}", flush=True)
            print(traceback.format_exc(), flush=True)


def _events_to_mididict(events: list[Any], *, ticks_per_beat: int, bpm: int) -> MidiDict:
    tempo_us_per_beat = round(60_000_000 / max(1, bpm))
    ticks_per_second = ticks_per_beat * bpm / 60.0

    note_msgs = []
    pedal_msgs = []

    for raw in events:
        if isinstance(raw, dict):
            event_type = raw.get("type")
        else:
            event_type = getattr(raw, "type", None)

        if event_type == "note":
            note = int(raw.get("note")) if isinstance(raw, dict) else int(getattr(raw, "note"))
            velocity = int(raw.get("velocity")) if isinstance(raw, dict) else int(getattr(raw, "velocity"))
            time_s = float(raw.get("time")) if isinstance(raw, dict) else float(getattr(raw, "time"))
            dur_s = float(raw.get("duration")) if isinstance(raw, dict) else float(getattr(raw, "duration"))

            start_tick = max(0, round(time_s * ticks_per_second))
            end_tick = max(start_tick, round((time_s + max(0.0, dur_s)) * ticks_per_second))
            note_msgs.append(
                {
                    "type": "note",
                    "data": {"pitch": note, "start": start_tick, "end": end_tick, "velocity": velocity},
                    "tick": start_tick,
                    "channel": 0,
                }
            )
        elif event_type == "cc":
            controller = int(raw.get("controller")) if isinstance(raw, dict) else int(getattr(raw, "controller"))
            value = int(raw.get("value")) if isinstance(raw, dict) else int(getattr(raw, "value"))
            time_s = float(raw.get("time")) if isinstance(raw, dict) else float(getattr(raw, "time"))
            tick = max(0, round(time_s * ticks_per_second))

            if controller == 64:
                pedal_msgs.append(
                    {
                        "type": "pedal",
                        "data": 1 if value >= 64 else 0,
                        "value": value,
                        "tick": tick,
                        "channel": 0,
                    }
                )

    return MidiDict(
        meta_msgs=[],
        tempo_msgs=[{"type": "tempo", "data": tempo_us_per_beat, "tick": 0}],
        pedal_msgs=pedal_msgs,
        instrument_msgs=[],
        note_msgs=note_msgs,
        ticks_per_beat=ticks_per_beat,
        metadata={},
    )


def main(argv: list[str] | None = None) -> None:
    config = parse_args(argv)
    run(config)


if __name__ == "__main__":
    main()
