from __future__ import annotations

import asyncio
import sys
import threading
import time
import types
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

from aiohttp.test_utils import TestClient, TestServer

from aria_server import server
from shared.aria_protocol import PROTOCOL_VERSION, ControlChangeEvent, GenerateRequest, NoteEvent
from shared.cc_policy import DefaultCCPolicy


class FailingPipeline:
    def generate(self, _: list[Any], __: dict[str, Any]) -> tuple[Any, int]:
        raise RuntimeError("model unavailable")


class SuccessfulPipeline:
    def generate(self, _: list[Any], __: dict[str, Any]) -> tuple[Any, int]:
        return object(), 137


class BusyPipeline:
    def generate(self, _: list[Any], __: dict[str, Any]) -> tuple[Any, int]:
        raise server.AriaBusyError("already running")


def _config() -> server.ServerConfig:
    return server.ServerConfig(
        host="127.0.0.1",
        port=0,
        checkpoint=Path("missing.safetensors"),
        engine="mlx",
        default_cc7=None,
        default_cc11=None,
    )


def _request_payload() -> dict[str, Any]:
    return {
        "type": "generate",
        "protocol_version": PROTOCOL_VERSION,
        "events": [
            {
                "type": "note",
                "note": 60,
                "velocity": 90,
                "time": 0.0,
                "duration": 0.25,
            },
            {"type": "cc", "controller": 64, "value": 127, "time": 0.1},
        ],
        "params": {"max_tokens": 16},
    }


def _test_app(pipeline: Any = None):
    app = server.create_app(_config())
    app.on_startup.clear()
    app.on_cleanup.clear()
    app[server.ARIA_PIPELINE_KEY] = pipeline or FailingPipeline()
    return app


def test_generate_failure_returns_typed_error_without_echoing_prompt() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app()))
        await client.start_server()
        try:
            response = await client.post("/generate", json=_request_payload())
            payload = await response.json()
            assert response.status == 500
            assert payload == {
                "type": "error",
                "protocol_version": PROTOCOL_VERSION,
                "code": "generation_failed",
                "message": None,
            }
            assert "events" not in payload
        finally:
            await client.close()

    asyncio.run(scenario())


def test_invalid_legacy_request_is_rejected_instead_of_ignored() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app()))
        await client.start_server()
        try:
            payload = _request_payload()
            payload["session_id"] = "legacy"
            payload["params"]["top_p"] = 0.9
            response = await client.post("/generate", json=payload)
            body = await response.json()
            assert response.status == 400
            assert body["type"] == "error"
            assert body["protocol_version"] == PROTOCOL_VERSION
            assert body["code"] == "invalid_request"
        finally:
            await client.close()

    asyncio.run(scenario())


def test_busy_generation_returns_machine_readable_503() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app(BusyPipeline())))
        await client.start_server()
        try:
            response = await client.post("/generate", json=_request_payload())
            payload = await response.json()
            assert response.status == 503
            assert payload == {
                "type": "error",
                "protocol_version": PROTOCOL_VERSION,
                "code": "busy",
                "message": "Aria inference is already running",
            }
        finally:
            await client.close()

    asyncio.run(scenario())


def test_pipeline_single_flight_rejects_second_call_without_waiting() -> None:
    pipeline = server.AriaPipeline(checkpoint=Path("missing.safetensors"), engine="mlx")
    assert pipeline._lock.acquire(blocking=False)
    started = time.perf_counter()
    try:
        try:
            pipeline.generate([], {"max_tokens": 16})
        except server.AriaBusyError:
            pass
        else:
            raise AssertionError("second Aria generation must fail busy")
    finally:
        pipeline._lock.release()
    assert time.perf_counter() - started < 0.05


def test_generated_reply_preserves_pipeline_latency_without_synthetic_cc64() -> None:
    async def scenario() -> None:
        app = _test_app(SuccessfulPipeline())
        app[server.CC_POLICY_KEY] = DefaultCCPolicy(default_cc7=None, default_cc11=None)

        midi_module = types.ModuleType("shared.aria_midi_events")
        midi_module.mididict_to_events = lambda _: []
        previous_module = sys.modules.get("shared.aria_midi_events")
        sys.modules["shared.aria_midi_events"] = midi_module
        try:
            request = GenerateRequest.model_validate(_request_payload())
            events, latency_ms = await server._generate_reply_events(app, request)
        finally:
            if previous_module is None:
                del sys.modules["shared.aria_midi_events"]
            else:
                sys.modules["shared.aria_midi_events"] = previous_module

        assert latency_ms == 137
        assert events == []

    asyncio.run(scenario())


def test_zero_cc_argument_remains_valid_and_out_of_range_is_rejected() -> None:
    assert server._parse_optional_cc_arg("0") == 0
    assert server._parse_optional_cc_arg("off") is None
    try:
        server._parse_optional_cc_arg("128")
    except Exception:
        pass
    else:
        raise AssertionError("out-of-range CC configuration must fail")


def test_continuation_extraction_removes_prompt_and_preserves_gap() -> None:
    prompt = [
        NoteEvent(note=60, velocity=90, time=0.0, duration=0.5),
        ControlChangeEvent(controller=64, value=0, time=1.0),
    ]
    reply = [
        *prompt,
        NoteEvent(note=67, velocity=88, time=1.25, duration=0.4),
    ]
    continuation = server._extract_continuation_events(prompt, reply)
    assert continuation == [NoteEvent(note=67, velocity=88, time=0.25, duration=0.4)]


def test_continuation_extraction_tolerates_generated_events_interleaved_by_time() -> None:
    prompt = [
        NoteEvent(note=60, velocity=90, time=0.0, duration=0.4),
        NoteEvent(note=64, velocity=84, time=1.0, duration=0.3),
    ]
    reply = [
        prompt[0],
        NoteEvent(note=67, velocity=76, time=0.75, duration=0.25),
        prompt[1],
    ]
    continuation = server._extract_continuation_events(prompt, reply)
    assert continuation == [NoteEvent(note=67, velocity=76, time=0.0, duration=0.25)]


def test_cuda_engine_can_be_selected_explicitly() -> None:
    config = server.parse_args(["--engine", "cuda"])
    assert config.engine == "cuda"


def test_cuda_pipeline_uses_torch_loader() -> None:
    from aria import run as aria_run

    model = object()
    with TemporaryDirectory() as directory:
        checkpoint = Path(directory) / "model.safetensors"
        checkpoint.touch()
        pipeline = server.AriaPipeline(checkpoint=checkpoint, engine="cuda")

        with (
            patch("torch.cuda.is_available", return_value=True),
            patch.object(aria_run, "_load_inference_model_torch", return_value=model) as torch_loader,
            patch.object(aria_run, "_load_inference_model_mlx") as mlx_loader,
        ):
            pipeline._ensure_loaded()

    torch_loader.assert_called_once_with(
        str(checkpoint),
        config_name="medium-emb",
        strict=False,
        vocab_size=pipeline._tokenizer.vocab_size,
    )
    mlx_loader.assert_not_called()
    assert pipeline._model is model


def test_cuda_pipeline_does_not_fall_back_to_mlx() -> None:
    from aria import run as aria_run

    with TemporaryDirectory() as directory:
        checkpoint = Path(directory) / "model.safetensors"
        checkpoint.touch()
        pipeline = server.AriaPipeline(checkpoint=checkpoint, engine="cuda")

        with (
            patch("torch.cuda.is_available", return_value=False),
            patch.object(aria_run, "_load_inference_model_torch") as torch_loader,
            patch.object(aria_run, "_load_inference_model_mlx") as mlx_loader,
        ):
            try:
                pipeline._ensure_loaded()
            except RuntimeError as error:
                assert str(error) == "CUDA engine selected but torch.cuda is unavailable"
            else:
                raise AssertionError("CUDA unavailability must fail without fallback")

    torch_loader.assert_not_called()
    mlx_loader.assert_not_called()
