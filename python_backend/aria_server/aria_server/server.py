from __future__ import annotations

import argparse
import asyncio
import logging
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from aiohttp import WSMsgType, web

from shared.cc_policy import DefaultCCPolicy, inject_defaults
from shared.protocol_v2 import (
    ALLOWED_CC_CONTROLLERS,
    ControlChangeEvent,
    ErrorResponseV2,
    GenerateRequestV2,
    ResultResponseV2,
    legalize_events,
)
from shared.streaming_protocol_v2 import StreamChunkV2, StreamStartRequestV2, StreamTimeRange

logger = logging.getLogger(__name__)
STREAM_START_TIMEOUT_SECONDS = 10.0


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
        self._tokenizer: Any | None = None
        self._model: Any | None = None

    def _ensure_loaded(self) -> None:
        if self._model is not None and self._tokenizer is not None:
            return

        from aria.run import _load_inference_model_mlx
        from ariautils.tokenizer import AbsTokenizer

        python_backend_dir = Path(__file__).resolve().parents[2]
        tokenizer_config = python_backend_dir / "aria" / "demo" / "demo-tokenizer-config.json"
        self._tokenizer = AbsTokenizer(config_path=tokenizer_config)

        if self._checkpoint.exists() is False:
            raise FileNotFoundError(f"checkpoint missing: {self._checkpoint}")

        self._model = _load_inference_model_mlx(
            str(self._checkpoint),
            config_name="medium-emb",
            strict=False,
        )
        logger.info("Aria model loaded")

    def generate(self, prompt_events: list[Any], params: dict[str, Any]) -> tuple[Any, int]:
        with self._lock:
            started = time.perf_counter()
            self._ensure_loaded()
            if self._tokenizer is None or self._model is None:
                raise RuntimeError("Aria model failed to initialize")

            from aria.inference import get_inference_prompt
            from aria.inference.sample_mlx import sample_batch
            from shared.midi_events_v2 import MidiBuildConfig, events_to_mididict

            midi_prompt = events_to_mididict(
                prompt_events,
                config=MidiBuildConfig(ticks_per_beat=480, bpm=120, channel=0),
            )
            prompt = get_inference_prompt(
                midi_dict=midi_prompt,
                tokenizer=self._tokenizer,
                prompt_len_ms=15_000,
            )

            max_new_tokens = int(params.get("max_tokens", 512))
            results = sample_batch(
                model=self._model,
                tokenizer=self._tokenizer,
                prompt=prompt,
                num_variations=1,
                max_new_tokens=max_new_tokens,
                temp=0.98,
                force_end=False,
                min_p=0.035,
                top_p=None,
            )
            if not results:
                raise RuntimeError("Aria model returned no generated sequence")

            reply = self._tokenizer.detokenize(results[0])
            if reply is None:
                raise RuntimeError("Aria tokenizer returned no MIDI reply")

            latency_ms = int(round((time.perf_counter() - started) * 1000))
            logger.info("Aria generation completed in %d ms", latency_ms)
            return reply, latency_ms


CONFIG_KEY = web.AppKey("config", ServerConfig)
ARIA_PIPELINE_KEY = web.AppKey("aria_pipeline", AriaPipeline)
CC_POLICY_KEY = web.AppKey("cc_policy", DefaultCCPolicy)
STREAM_WINDOW_KEY = web.AppKey("stream_window_s", float)
STREAM_START_TIMEOUT_KEY = web.AppKey("stream_start_timeout_s", float)
BONJOUR_BROADCASTER_KEY = web.AppKey("bonjour_broadcaster", object)


def _chunk_events(events: list[Any], *, window_s: float) -> list[tuple[float, float, list[Any]]]:
    if not events:
        return [(0.0, 0.0, [])]

    def event_end_time(event: Any) -> float:
        if isinstance(event, ControlChangeEvent):
            return float(event.time)
        duration = getattr(event, "duration", None)
        if duration is None:
            return float(getattr(event, "time", 0.0))
        return float(getattr(event, "time", 0.0)) + max(0.0, float(duration))

    max_end = max(event_end_time(event) for event in events)
    window_s = max(0.05, float(window_s))
    chunks: list[tuple[float, float, list[Any]]] = []

    start = 0.0
    while start <= max_end + 1e-9:
        end = start + window_s
        slice_events = [
            event
            for event in events
            if start <= float(getattr(event, "time", 0.0)) < end
        ]
        chunks.append((start, min(end, max_end), slice_events))
        start = end

    if chunks and chunks[-1][1] < max_end:
        chunks.append((chunks[-1][1], max_end, []))

    return chunks


async def _generate_reply_events(
    app: web.Application,
    request_model: GenerateRequestV2,
) -> tuple[list[Any], int]:
    pipeline: AriaPipeline = app[ARIA_PIPELINE_KEY]
    policy: DefaultCCPolicy = app[CC_POLICY_KEY]

    reply_midi, latency_ms = await asyncio.to_thread(
        pipeline.generate,
        request_model.events,
        request_model.params.model_dump(),
    )

    from shared.midi_events_v2 import mididict_to_events

    events = legalize_events(mididict_to_events(reply_midi))

    # Always include at least one CC64 at time=0 for downstream stability.
    if not any(
        isinstance(event, ControlChangeEvent) and event.controller == 64
        for event in events
    ):
        events = legalize_events(
            [ControlChangeEvent(controller=64, value=0, time=0.0), *events]
        )

    return inject_defaults(events, policy=policy), latency_ms


def _generation_error() -> ErrorResponseV2:
    return ErrorResponseV2(message="generation_failed")


async def handle_root(_: web.Request) -> web.Response:
    return web.Response(
        text="aria_server running. POST /generate or WS /stream (protocol_version=2).\n"
    )


async def handle_generate(request: web.Request) -> web.Response:
    try:
        payload = await request.json()
    except Exception:
        return web.json_response(
            ErrorResponseV2(message="invalid_json").model_dump(),
            status=400,
        )

    try:
        request_model = GenerateRequestV2.model_validate(payload)
    except Exception as exc:
        return web.json_response(
            ErrorResponseV2(message=f"invalid_request: {exc}").model_dump(),
            status=400,
        )

    try:
        events, latency_ms = await _generate_reply_events(request.app, request_model)
    except Exception:
        logger.exception("Aria HTTP generation failed")
        return web.json_response(_generation_error().model_dump(), status=500)

    response = ResultResponseV2(events=events, latency_ms=latency_ms)
    return web.json_response(response.model_dump(), status=200)


async def handle_stream(request: web.Request) -> web.StreamResponse:
    ws = web.WebSocketResponse(heartbeat=30.0)
    await ws.prepare(request)

    try:
        async with asyncio.timeout(request.app[STREAM_START_TIMEOUT_KEY]):
            message = await ws.receive()
    except TimeoutError:
        await ws.send_json(ErrorResponseV2(message="start_timeout").model_dump())
        await ws.close(message=b"start timeout")
        return ws

    if message.type != WSMsgType.TEXT:
        await ws.send_json(ErrorResponseV2(message="expected_text_start").model_dump())
        await ws.close(message=b"expected text start message")
        return ws

    try:
        start_payload = StreamStartRequestV2.model_validate_json(message.data)
    except Exception as exc:
        await ws.send_json(
            ErrorResponseV2(message=f"invalid_start: {exc}").model_dump()
        )
        await ws.close()
        return ws

    try:
        events, latency_ms = await _generate_reply_events(
            request.app,
            start_payload.request,
        )
    except Exception:
        logger.exception("Aria WebSocket generation failed")
        await ws.send_json(_generation_error().model_dump())
        await ws.close(message=b"generation failed")
        return ws

    window_s: float = request.app[STREAM_WINDOW_KEY]
    chunks = _chunk_events(events, window_s=window_s)

    for sequence, (start_s, end_s, slice_events) in enumerate(chunks):
        chunk = StreamChunkV2(
            seq=sequence,
            is_final=False,
            time_range=StreamTimeRange(start=start_s, end=end_s),
            events=slice_events,
            latency_ms=latency_ms if sequence == 0 else None,
        ).legalized()
        await ws.send_json(chunk.model_dump())

    final_time = chunks[-1][1]
    final_chunk = StreamChunkV2(
        seq=len(chunks),
        is_final=True,
        time_range=StreamTimeRange(start=final_time, end=final_time),
        events=[],
        latency_ms=None,
    )
    await ws.send_json(final_chunk.model_dump())
    await ws.close()
    return ws


async def _bonjour_start(app: web.Application) -> None:
    from shared.bonjour import BonjourServiceBroadcaster

    config: ServerConfig = app[CONFIG_KEY]
    txt = {
        "path": "/generate",
        "ws_path": "/stream",
        "protocol_version": "2",
        "engine": "aria",
        "engine_impl": "aria",
    }

    broadcaster = BonjourServiceBroadcaster(
        service_type="_lpduet._tcp",
        instance_name="HappyPianist Aria",
        port=config.port,
        properties={key.encode("utf-8"): value.encode("utf-8") for key, value in txt.items()},
    )
    await broadcaster.start()
    app[BONJOUR_BROADCASTER_KEY] = broadcaster


async def _bonjour_stop(app: web.Application) -> None:
    broadcaster = app.get(BONJOUR_BROADCASTER_KEY)
    if broadcaster is not None:
        await broadcaster.stop()


def create_app(
    config: ServerConfig,
    *,
    stream_start_timeout_s: float = STREAM_START_TIMEOUT_SECONDS,
) -> web.Application:
    app = web.Application()
    app[CONFIG_KEY] = config
    app[ARIA_PIPELINE_KEY] = AriaPipeline(checkpoint=config.checkpoint)
    app[CC_POLICY_KEY] = DefaultCCPolicy(
        default_cc7=config.default_cc7,
        default_cc11=config.default_cc11,
    )
    app[STREAM_WINDOW_KEY] = config.stream_window_s
    app[STREAM_START_TIMEOUT_KEY] = stream_start_timeout_s

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
