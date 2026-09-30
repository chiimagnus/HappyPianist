from __future__ import annotations

import asyncio
import threading
import time
from typing import Any

import pytest
from aiohttp.test_utils import TestClient, TestServer
from pydantic import ValidationError

from qwen_server import server
from shared.companion_semantics import build_semantic_prompt, semantic_question_ids
from shared.qwen_companion_protocol import (
    COMPANION_DECISION_PATH,
    ENGINE_ID,
    MODEL_ID,
    PROTOCOL_VERSION,
    CompanionDecisionRequest,
    CompanionDecisionResponse,
    CompanionUsage,
    SemanticValues,
)


class FixedRuntime:
    def decide(
        self,
        request: CompanionDecisionRequest,
        *,
        server_started: float,
    ) -> CompanionDecisionResponse:
        assert request.state.held_notes_count == 1
        assert server_started > 0
        return CompanionDecisionResponse(
            action="support",
            semantic_scores=SemanticValues(
                continuing=0.8,
                finished=0.2,
                space=0.9,
                reasserted=0.1,
            ),
            semantic_order_gaps=SemanticValues(
                continuing=0.04,
                finished=0.03,
                space=0.02,
                reasserted=0.01,
            ),
            usage=CompanionUsage(input_tokens=123, output_tokens=0),
            server_latency_ms=17,
        )


class FailingRuntime:
    def decide(self, *_: Any, **__: Any) -> Any:
        raise RuntimeError("model failed")


def _config() -> server.ServerConfig:
    return server.ServerConfig(host="127.0.0.1", port=0)


def _state() -> dict[str, Any]:
    return {
        "held_notes_count": 1,
        "sustain_value": 0,
        "recent_ioi_median_seconds": 0.42,
        "recent_note_density_per_second": 1.5,
        "seconds_since_last_note_on": 0.1,
        "is_ai_playback_active": False,
        "user_note_on_since_ai_playback_started": False,
    }


def _payload() -> dict[str, Any]:
    return {"state": _state()}


def _test_app(runtime: Any):
    app = server.create_app(_config())
    app.on_startup.clear()
    app.on_cleanup.clear()
    app[server.RUNTIME_KEY] = runtime
    return app


def test_companion_request_is_strict_and_has_no_model_or_questions() -> None:
    request = CompanionDecisionRequest.model_validate(_payload())
    assert request.state.recent_note_density_per_second == 1.5

    with pytest.raises(ValidationError):
        CompanionDecisionRequest.model_validate({**_payload(), "model": MODEL_ID})
    with pytest.raises(ValidationError):
        CompanionDecisionRequest.model_validate({**_payload(), "questions": {}})
    with pytest.raises(ValidationError):
        CompanionDecisionRequest.model_validate(
            {"state": {**_state(), "unexpected_legacy_field": []}}
        )


def test_semantic_prompt_is_fixed_binary_and_order_swapped() -> None:
    true_a = build_semantic_prompt(_state(), "finished__true_a")
    true_b = build_semantic_prompt(_state(), "finished__true_b")

    assert true_a.labels == ["A", "B"]
    assert true_b.labels == ["A", "B"]
    assert true_a.answer_prefix == '{"answer": "'
    assert "held_notes_count == 0" in true_a.messages[1]["content"]
    assert "held_notes_count > 0" in true_a.messages[1]["content"]
    assert true_a.messages[1]["content"] != true_b.messages[1]["content"]
    assert len(semantic_question_ids()) == 8


def test_companion_endpoint_returns_typed_zero_output_decision() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app(FixedRuntime())))
        await client.start_server()
        try:
            response = await client.post(COMPANION_DECISION_PATH, json=_payload())
            payload = await response.json()

            assert response.status == 200
            assert payload["model"] == MODEL_ID
            assert payload["action"] == "support"
            assert payload["semantic_scores"]["space"] == 0.9
            assert payload["semantic_order_gaps"]["space"] == 0.02
            assert payload["usage"]["output_tokens"] == 0
            assert payload["server_latency_ms"] == 17
        finally:
            await client.close()

    asyncio.run(scenario())


def test_companion_endpoint_rejects_generic_classifier_payload() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app(FixedRuntime())))
        await client.start_server()
        try:
            response = await client.post(
                COMPANION_DECISION_PATH,
                json={**_payload(), "model": MODEL_ID, "questions": {}},
            )
            payload = await response.json()
            assert response.status == 400
            assert payload["code"] == "invalid_request"
        finally:
            await client.close()

    asyncio.run(scenario())


def test_companion_busy_is_fail_fast_while_first_inference_is_running() -> None:
    class BlockingRuntime(server.TransformersQwenRuntime):
        def __init__(self) -> None:
            super().__init__()
            self.started = threading.Event()
            self.release = threading.Event()

        def _decide_admitted(
            self,
            request: CompanionDecisionRequest,
            *,
            server_started: float,
        ) -> CompanionDecisionResponse:
            assert request.state.held_notes_count == 1
            assert server_started > 0
            self.started.set()
            if not self.release.wait(timeout=2):
                raise RuntimeError("test inference was not released")
            return CompanionDecisionResponse(
                action="support",
                semantic_scores=SemanticValues(
                    continuing=0.8,
                    finished=0.2,
                    space=0.9,
                    reasserted=0.1,
                ),
                semantic_order_gaps=SemanticValues(
                    continuing=0.04,
                    finished=0.03,
                    space=0.02,
                    reasserted=0.01,
                ),
                usage=CompanionUsage(input_tokens=123, output_tokens=0),
                server_latency_ms=17,
            )

    async def scenario() -> None:
        runtime = BlockingRuntime()
        client = TestClient(TestServer(_test_app(runtime)))
        await client.start_server()
        first_task: asyncio.Task[Any] | None = None
        try:
            first_task = asyncio.create_task(
                client.post(COMPANION_DECISION_PATH, json=_payload())
            )
            assert await asyncio.to_thread(runtime.started.wait, 1)

            started = time.perf_counter()
            second = await client.post(COMPANION_DECISION_PATH, json=_payload())
            elapsed = time.perf_counter() - started
            second_payload = await second.json()

            assert second.status == 503
            assert second_payload["code"] == "busy"
            assert "action" not in second_payload
            assert elapsed < 0.2
            assert first_task.done() is False

            runtime.release.set()
            first = await first_task
            assert first.status == 200
        finally:
            runtime.release.set()
            if first_task is not None and first_task.done() is False:
                await first_task
            await client.close()

    asyncio.run(scenario())


def test_companion_failure_does_not_invent_an_action() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app(FailingRuntime())))
        await client.start_server()
        try:
            response = await client.post(COMPANION_DECISION_PATH, json=_payload())
            payload = await response.json()
            assert response.status == 500
            assert payload["code"] == "decision_failed"
            assert "action" not in payload
        finally:
            await client.close()

    asyncio.run(scenario())


def test_candidate_boundary_rejects_non_single_token_ab_labels() -> None:
    class UnstableTokenizer:
        pad_token_id = 0
        eos_token_id = 0

        def apply_chat_template(self, *_: Any, **__: Any) -> str:
            return "prompt"

        def encode(self, text: str, *, add_special_tokens: bool) -> list[int]:
            assert add_special_tokens is False
            if text.endswith("A") or text.endswith("B"):
                return [1, 2, 99, 100]
            return [1, 2, 3]

    runtime = server.TransformersQwenRuntime()
    runtime._tokenizer = UnstableTokenizer()

    with pytest.raises(RuntimeError, match="not single-token stable"):
        runtime._compile_question(_state(), "continuing__true_a")


def test_server_identity_is_fixed_to_qwen_cuda_companion() -> None:
    config = server.parse_args(["--host", "0.0.0.0", "--port", "9000"])
    assert config.host == "0.0.0.0"
    assert config.port == 9000
    assert MODEL_ID == "Qwen3.5-0.8B-NF4-4bit"
    assert ENGINE_ID == "qwen-companion"
    assert PROTOCOL_VERSION == "2"

    with pytest.raises(SystemExit):
        server.parse_args(["--model", "other-model"])
    with pytest.raises(SystemExit):
        server.parse_args(["--device", "cpu"])
