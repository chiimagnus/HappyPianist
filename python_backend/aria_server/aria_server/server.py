from __future__ import annotations

import argparse
import asyncio
import time
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from aiohttp import WSMsgType, web

from shared.bonjour import BonjourServiceBroadcaster
from shared.cc_policy import DefaultCCPolicy, inject_defaults
from shared.midi_events_v2 import MidiBuildConfig, events_to_mididict, mididict_to_events
from shared.protocol_v2 import (
    ALLOWED_CC_CONTROLLERS,
    ControlChangeEvent,
    ErrorResponseV2,
    GenerateRequestV2,
    ResultResponseV2,
    legalize_events,
)
from shared.streaming_protocol_v2 import StreamChunkV2, StreamStartRequestV2, StreamTimeRange

from aria.run import _load_inference_model_mlx
from aria.inference import get_inference_prompt
from aria.inference.sample_mlx import sample_batch
from ariautils.midi import MidiDict
from ariautils.tokenizer import AbsTokenizer


@dataclass(frozen=True)
class ServerConfig:
    host: str
    port: int
    checkpoint: Path
    default_cc7: int | None
    default_cc11: int | None
    stream_window_s: float


def _default_checkpoint_path() -> Path:
    python_backend_dir = Path(__file__).resolve().parents[2]
    return python_backend_dir / "aria" / "hf" / "model-demo.safetensors"


def _parse_optional_cc_arg(raw: str) -> int | None:
    value = raw.strip().lower()
    if value in {"none", "off", "disable", "disabled", ""}:
        return None
    try:
        parsed = int(raw)
    except ValueError:
        raise argparse.ArgumentTypeError(f"invalid cc value: {raw!r}") from None
    if parsed == 0:
        # Convention: treat 0 as "disabled" (even though 0 is a legal CC value).
        return None
    return max(0, min(127, parsed))


def parse_args(argv: list[str] | None = None) -> ServerConfig:
    parser = argparse.ArgumentParser(prog="aria_server", add_help=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--checkpoint", type=Path, default=_default_checkpoint_path())
    parser.add_argument("--default_cc7", default="100")
    parser.add_argument("--default_cc11", default="100")
    parser.add_argument("--stream_window", type=float, default=0.5)
    args = parser.parse_args(argv)

    return ServerConfig(
        host=args.host,
        port=args.port,
        checkpoint=args.checkpoint,
        default_cc7=_parse_optional_cc_arg(args.default_cc7),
        default_cc11=_parse_optional_cc_arg(args.default_cc11),
        stream_window_s=max(0.05, float(args.stream_window)),
    )


class AriaPipeline:
    def __init__(self, checkpoint: Path):
        self._checkpoint = checkpoint
        self._lock = threading.Lock()
        self._tokenizer: AbsTokenizer | None = None
        self._model = None

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

    def generate_best_effort(self, prompt_events: list[Any], params: dict[str, Any]) -> MidiDict | None:
        try:
            with self._lock:
                started = time.perf_counter()
                self._ensure_loaded()
                assert self._tokenizer is not None
                assert self._model is not None

                midi_prompt = events_to_mididict(
                    prompt_events,
                    config=MidiBuildConfig(ticks_per_beat=480, bpm=120, channel=0),
                )
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
                reply: MidiDict | None = None
                if results:
                    reply = self._tokenizer.detokenize(results[0])

                elapsed_ms = int(round((time.perf_counter() - started) * 1000))
                print(f"[aria_server] generation done in {elapsed_ms}ms", flush=True)
                return reply
        except Exception as exc:
            import traceback

            print(f"[aria_server] generate_best_effort failed: {exc}", flush=True)
            print(traceback.format_exc(), flush=True)
            return None


def _chunk_events(events: list[Any], *, window_s: float) -> list[tuple[float, float, list[Any]]]:
    if not events:
        return [(0.0, 0.0, [])]

    def event_end_time(e: Any) -> float:
        if isinstance(e, ControlChangeEvent):
            return float(e.time)
        duration = getattr(e, "duration", None)
        if duration is None:
            return float(getattr(e, "time", 0.0))
        return float(getattr(e, "time", 0.0)) + max(0.0, float(duration))

    max_end = max(event_end_time(e) for e in events)
    window_s = max(0.05, float(window_s))
    chunks: list[tuple[float, float, list[Any]]] = []

    start = 0.0
    while start <= max_end + 1e-9:
        end = start + window_s
        slice_events = [e for e in events if start <= float(getattr(e, "time", 0.0)) < end]
        chunks.append((start, min(end, max_end), slice_events))
        start = end

    if chunks and chunks[-1][1] < max_end:
        chunks.append((chunks[-1][1], max_end, []))

    return chunks


async def _generate_reply_events(app: web.Application, request_model: GenerateRequestV2) -> list[Any]:
    pipeline: AriaPipeline = app["aria_pipeline"]
    policy: DefaultCCPolicy = app["cc_policy"]

    reply_midi = await asyncio.to_thread(pipeline.generate_best_effort, request_model.events, request_model.params.model_dump())
    if reply_midi is None:
        events = legalize_events(request_model.events)
    else:
        events = legalize_events(mididict_to_events(reply_midi))

    # Always include at least one CC64 at time=0 for downstream stability.
    if not any(isinstance(e, ControlChangeEvent) and e.controller == 64 for e in events):
        events = legalize_events([ControlChangeEvent(controller=64, value=0, time=0.0)] + events)

    events = inject_defaults(events, policy=policy)
    return events


async def handle_root(_: web.Request) -> web.Response:
    return web.Response(text="aria_server running. POST /generate or WS /stream (protocol_version=2).\n")


async def handle_generate(request: web.Request) -> web.Response:
    try:
        payload = await request.json()
    except Exception:
        return web.json_response(ErrorResponseV2(message="invalid_json").model_dump(), status=400)

    try:
        request_model = GenerateRequestV2.model_validate(payload)
    except Exception as exc:
        return web.json_response(ErrorResponseV2(message=f"invalid_request: {exc}").model_dump(), status=400)

    events = await _generate_reply_events(request.app, request_model)
    response = ResultResponseV2(events=events, latency_ms=0)
    return web.json_response(response.model_dump(), status=200)


async def handle_stream(request: web.Request) -> web.StreamResponse:
    ws = web.WebSocketResponse(heartbeat=30.0)
    await ws.prepare(request)

    msg = await ws.receive()
    if msg.type != WSMsgType.TEXT:
        await ws.close(message=b"expected text start message")
        return ws

    try:
        start_payload = StreamStartRequestV2.model_validate_json(msg.data)
    except Exception as exc:
        err = ErrorResponseV2(message=f"invalid_start: {exc}").model_dump()
        await ws.send_json(err)
        await ws.close()
        return ws

    events = await _generate_reply_events(request.app, start_payload.request)
    window_s: float = request.app["stream_window_s"]

    chunks = _chunk_events(events, window_s=window_s)
    for seq, (start_s, end_s, slice_events) in enumerate(chunks):
        chunk = StreamChunkV2(
            seq=seq,
            is_final=False,
            time_range=StreamTimeRange(start=start_s, end=end_s),
            events=slice_events,
            latency_ms=None,
        ).legalized()
        await ws.send_json(chunk.model_dump())

    final_chunk = StreamChunkV2(
        seq=len(chunks),
        is_final=True,
        time_range=StreamTimeRange(start=chunks[-1][1], end=chunks[-1][1]),
        events=[],
        latency_ms=None,
    )
    await ws.send_json(final_chunk.model_dump())
    await ws.close()
    return ws


async def _bonjour_start(app: web.Application) -> None:
    config: ServerConfig = app["config"]
    txt = {
        "path": "/generate",
        "ws_path": "/stream",
        "protocol_version": "2",
        "engine": "aria",
        "engine_impl": "aria",
    }

    broadcaster = BonjourServiceBroadcaster(
        service_type="_lpduet._tcp",
        instance_name="LonelyPianist Aria",
        port=config.port,
        properties={k.encode("utf-8"): v.encode("utf-8") for k, v in txt.items()},
    )
    await broadcaster.start()
    app["bonjour_broadcaster"] = broadcaster


async def _bonjour_stop(app: web.Application) -> None:
    broadcaster: BonjourServiceBroadcaster | None = app.get("bonjour_broadcaster")
    if broadcaster is not None:
        await broadcaster.stop()


def create_app(config: ServerConfig) -> web.Application:
    app = web.Application()
    app["config"] = config
    app["aria_pipeline"] = AriaPipeline(checkpoint=config.checkpoint)
    app["cc_policy"] = DefaultCCPolicy(default_cc7=config.default_cc7, default_cc11=config.default_cc11)
    app["stream_window_s"] = config.stream_window_s

    app.router.add_get("/", handle_root)
    app.router.add_post("/generate", handle_generate)
    app.router.add_get("/stream", handle_stream)

    app.on_startup.append(_bonjour_start)
    app.on_cleanup.append(_bonjour_stop)
    return app


def main(argv: list[str] | None = None) -> None:
    config = parse_args(argv)
    print(f"[aria_server] checkpoint={config.checkpoint}", flush=True)
    print(f"[aria_server] listening=http://{config.host}:{config.port}", flush=True)
    print(f"[aria_server] allowed_cc={sorted(ALLOWED_CC_CONTROLLERS)}", flush=True)
    print(f"[aria_server] stream_window_s={config.stream_window_s}", flush=True)

    app = create_app(config)
    web.run_app(app, host=config.host, port=config.port, print=None)


if __name__ == "__main__":
    main()

