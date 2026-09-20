from __future__ import annotations

import asyncio
from typing import Any

from aiohttp.test_utils import TestClient, TestServer

from companion_decision_server import server
from shared.decision_protocol import CompanionDecisionInputV2


class FixedPipeline:
    def decide(
        self,
        _: CompanionDecisionInputV2,
    ) -> tuple[str, float, dict[str, float], int]:
        return (
            "respond",
            0.91,
            {
                "listen": 0.03,
                "support": 0.02,
                "sparse": 0.02,
                "yield": 0.02,
                "respond": 0.91,
            },
            87,
        )


class FailingPipeline:
    def decide(self, _: CompanionDecisionInputV2) -> Any:
        raise RuntimeError("model failed")


def _config() -> server.ServerConfig:
    return server.ServerConfig(
        host="127.0.0.1",
        port=0,
        model="Qwen/Qwen3.5-0.8B",
        device="cuda",
    )


def _payload() -> dict[str, Any]:
    return {
        "protocol_version": 2,
        "input": {
            "now_timestamp_seconds": 100.0,
            "held_notes_count": 0,
            "sustain_value": 0,
            "recent_ioi_median_seconds": 0.42,
            "recent_velocity_trend": -8.0,
            "recent_note_density_per_second": 1.1,
            "last_user_event_timestamp_seconds": 99.3,
            "last_note_on_timestamp_seconds": 99.3,
            "active_pitch_center": 60.0,
            "is_ai_playback_active": False,
            "recent_notes": [
                {
                    "midi": 60,
                    "velocity": 80,
                    "onset_seconds_ago": 0.8,
                    "duration_seconds": 0.3,
                }
            ],
        },
    }


def _test_app(pipeline: Any):
    app = server.create_app(_config())
    app.on_startup.clear()
    app.on_cleanup.clear()
    app[server.PIPELINE_KEY] = pipeline
    return app


def test_decision_endpoint_returns_typed_action_and_probabilities() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app(FixedPipeline())))
        await client.start_server()
        try:
            response = await client.post("/decision", json=_payload())
            payload = await response.json()
            assert response.status == 200
            assert payload["protocol_version"] == 2
            assert payload["action"] == "respond"
            assert payload["confidence"] == 0.91
            assert payload["probabilities"]["respond"] == 0.91
            assert payload["latency_ms"] == 87
            assert payload["model"] == "Qwen/Qwen3.5-0.8B"
        finally:
            await client.close()

    asyncio.run(scenario())


def test_decision_failure_does_not_fall_back_to_rule_action() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app(FailingPipeline())))
        await client.start_server()
        try:
            response = await client.post("/decision", json=_payload())
            payload = await response.json()
            assert response.status == 500
            assert payload == {
                "protocol_version": 2,
                "message": "decision_failed",
            }
            assert "action" not in payload
        finally:
            await client.close()

    asyncio.run(scenario())


def test_state_formatter_includes_recent_midi_and_ai_playback_state() -> None:
    input_model = CompanionDecisionInputV2.model_validate(_payload()["input"])
    text = server.format_decision_state(input_model)

    assert "AI当前正在演奏=否" in text
    assert "60(v=80,ago=0.800s,d=0.300s)" in text
    assert "距最后一次按键=0.700秒" in text


def test_breaking_note_schema_rejects_protocol_v1() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app(FixedPipeline())))
        await client.start_server()
        try:
            payload = _payload()
            payload["protocol_version"] = 1
            response = await client.post("/decision", json=payload)
            body = await response.json()
            assert response.status == 400
            assert body["protocol_version"] == 2
            assert body["message"].startswith("invalid_request:")
        finally:
            await client.close()

    asyncio.run(scenario())

def test_device_selection_is_explicit() -> None:
    assert server.parse_args(["--device", "cuda"]).device == "cuda"
    assert server.parse_args(["--device", "cpu"]).device == "cpu"
