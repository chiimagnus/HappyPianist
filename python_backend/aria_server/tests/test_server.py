from __future__ import annotations

import asyncio
import json
import sys
import types
from pathlib import Path
from typing import Any

from aiohttp import WSMsgType
from aiohttp.test_utils import TestClient, TestServer

from aria_server import server
from shared.cc_policy import DefaultCCPolicy
from shared.protocol_v2 import GenerateRequestV2


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
