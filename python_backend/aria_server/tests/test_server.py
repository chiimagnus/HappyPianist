from __future__ import annotations

import asyncio
import json
import sys
import types
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from unittest.mock import patch

from aiohttp import WSMsgType
from aiohttp.test_utils import TestClient, TestServer

from aria_server import server
from shared.cc_policy import DefaultCCPolicy
from shared.protocol_v2 import ControlChangeEvent, GenerateRequestV2, NoteEvent


class FailingPipeline:
    def generate(self, _: list[Any], __: dict[str, Any]) -> tuple[Any, int]:
        raise RuntimeError("model unavailable")


class SuccessfulPipeline:
    def generate(self, _: list[Any], __: dict[str, Any]) -> tuple[Any, int]:
        return object(), 137


def _config() -> server.ServerConfig:
    return server.ServerConfig(
        host="127.0.0.1",
        port=0,
        checkpoint=Path("missing.safetensors"),
        engine="mlx",
        default_cc7=None,
        default_cc11=None,
        stream_window_s=0.5,
    )


def _request_payload() -> dict[str, Any]:
    return {
        "type": "generate",
        "protocol_version": 2,
        "events": [
            {
                "type": "note",
                "note": 60,
                "velocity": 90,
                "time": 0.0,
                "duration": 0.25,
            }
        ],
        "params": {
            "top_p": 0.9,
            "max_tokens": 16,
            "strategy": "test",
        },
        "session_id": "server-test",
    }


def _test_app(*, timeout: float = 0.05):
    app = server.create_app(_config(), stream_start_timeout_s=timeout)
    app.on_startup.clear()
    app.on_cleanup.clear()
    app[server.ARIA_PIPELINE_KEY] = FailingPipeline()
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
                "protocol_version": 2,
                "message": "generation_failed",
            }
            assert "events" not in payload
        finally:
            await client.close()

    asyncio.run(scenario())


def test_stream_closes_when_start_message_never_arrives() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app(timeout=0.01)))
        await client.start_server()
        try:
            websocket = await client.ws_connect("/stream")
            message = await websocket.receive(timeout=1)

            assert message.type == WSMsgType.TEXT
            assert json.loads(message.data) == {
                "type": "error",
                "protocol_version": 2,
                "message": "start_timeout",
            }

            close_message = await websocket.receive(timeout=1)
            assert close_message.type in {
                WSMsgType.CLOSE,
                WSMsgType.CLOSED,
                WSMsgType.CLOSING,
            }
        finally:
            await client.close()

    asyncio.run(scenario())


def test_stream_generation_failure_sends_error_instead_of_chunk() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app()))
        await client.start_server()
        try:
            websocket = await client.ws_connect("/stream")
            await websocket.send_json(
                {
                    "type": "start",
                    "protocol_version": 2,
                    "request": _request_payload(),
                }
            )
            message = await websocket.receive(timeout=1)

            assert message.type == WSMsgType.TEXT
            assert json.loads(message.data) == {
                "type": "error",
                "protocol_version": 2,
                "message": "generation_failed",
            }
        finally:
            await client.close()

    asyncio.run(scenario())


def test_generated_reply_preserves_pipeline_latency() -> None:
    async def scenario() -> None:
        app = server.create_app(_config())
        app[server.ARIA_PIPELINE_KEY] = SuccessfulPipeline()
        app[server.CC_POLICY_KEY] = DefaultCCPolicy(default_cc7=None, default_cc11=None)

        midi_module = types.ModuleType("shared.midi_events_v2")
        midi_module.mididict_to_events = lambda _: []
        previous_module = sys.modules.get("shared.midi_events_v2")
        sys.modules["shared.midi_events_v2"] = midi_module
        try:
            request = GenerateRequestV2.model_validate(_request_payload())
            events, latency_ms = await server._generate_reply_events(app, request)
        finally:
            if previous_module is None:
                del sys.modules["shared.midi_events_v2"]
            else:
                sys.modules["shared.midi_events_v2"] = previous_module

        assert latency_ms == 137
        assert any(getattr(event, "controller", None) == 64 for event in events)

    asyncio.run(scenario())


def test_zero_cc_argument_remains_a_valid_midi_value() -> None:
    assert server._parse_optional_cc_arg("0") == 0
    assert server._parse_optional_cc_arg("off") is None


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
