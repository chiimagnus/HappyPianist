from __future__ import annotations

import asyncio
from typing import Any

import pytest
from aiohttp.test_utils import TestClient, TestServer
from pydantic import ValidationError

from qwen_server import server
from shared.qwen_protocol import (
    ChoiceAnswer,
    ChoiceQuestion,
    ClassifierRequest,
    ClassifierResponse,
    ClassifierUsage,
    build_choice_prompt,
)


class FixedRuntime:
    def classify(self, request: ClassifierRequest) -> ClassifierResponse:
        question = request.questions["route"]
        assert question.type == "choice"
        return ClassifierResponse(
            model=request.model,
            answers={
                "route": ChoiceAnswer(
                    choice="billing",
                    confidence=0.8,
                    probabilities={"billing": 0.8, "technical": 0.2},
                )
            },
            usage=ClassifierUsage(input_tokens=42, output_tokens=0),
            latency_ms=11,
        )


class FailingRuntime:
    def classify(self, _: ClassifierRequest) -> Any:
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
        "model": "Qwen/Qwen3.5-0.8B",
        "state": {
            "message": "I was charged twice.",
            "customer_tier": "pro",
        },
        "questions": {
            "route": {
                "type": "choice",
                "instructions": "Which team should handle this request?",
                "criteria": {
                    "billing": "Payments, invoices, and refunds.",
                    "technical": "Product errors and technical failures.",
                },
            }
        },
    }


def _test_app(runtime: Any):
    app = server.create_app(_config())
    app.on_startup.clear()
    app.on_cleanup.clear()
    app[server.RUNTIME_KEY] = runtime
    return app


def test_choice_prompt_is_domain_agnostic_and_deterministic() -> None:
    request = ClassifierRequest.model_validate(_payload())
    question = request.questions["route"]

    plan = build_choice_prompt(request.state, request.questions, "route")

    assert plan.labels == ["A", "B"]
    assert plan.choices == ["billing", "technical"]
    assert "customer_tier" in plan.messages[1]["content"]
    assert "billing" in plan.messages[1]["content"]
    assert plan.answer_prefix == '{"answer": "'
    assert "piano" not in plan.messages[0]["content"].lower()

    reversed_question = ChoiceQuestion(
        instructions=question.instructions,
        criteria={
            "technical": question.criteria["technical"],
            "billing": question.criteria["billing"],
        },
    )
    reversed_plan = build_choice_prompt(
        request.state,
        {"route": reversed_question},
        "route",
    )
    assert reversed_plan.choices == plan.choices
    assert reversed_plan.messages[1]["content"] == plan.messages[1]["content"]


def test_shared_system_question_order_is_deterministic() -> None:
    route = ChoiceQuestion(
        instructions="Choose a route.",
        criteria={"billing": None, "technical": None},
    )
    urgency = ChoiceQuestion(
        instructions="Choose urgency.",
        criteria={"high": None, "low": None},
    )
    state = {"message": "hello"}

    first = build_choice_prompt(state, {"route": route, "urgency": urgency}, "route")
    reversed_order = build_choice_prompt(
        state,
        {"urgency": urgency, "route": route},
        "route",
    )

    assert first.messages == reversed_order.messages


def test_choice_question_requires_at_least_two_candidates_without_arbitrary_maximum() -> None:
    with pytest.raises(ValidationError):
        ChoiceQuestion(instructions="Choose.", criteria={"only": None})

    question = ChoiceQuestion(
        instructions="Choose.",
        criteria={f"candidate-{index}": None for index in range(30)},
    )
    assert len(question.criteria) == 30


def test_classifier_request_requires_at_least_one_question() -> None:
    with pytest.raises(ValidationError):
        ClassifierRequest(model="test", state={}, questions={})


def test_classifier_endpoint_returns_typed_choice_without_output_tokens() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app(FixedRuntime())))
        await client.start_server()
        try:
            response = await client.post("/v1/classifier", json=_payload())
            payload = await response.json()

            assert response.status == 200
            assert payload["model"] == "Qwen/Qwen3.5-0.8B"
            assert payload["answers"]["route"]["type"] == "choice"
            assert payload["answers"]["route"]["choice"] == "billing"
            assert payload["answers"]["route"]["probabilities"]["billing"] == 0.8
            assert payload["usage"]["output_tokens"] == 0
            assert payload["latency_ms"] == 11
        finally:
            await client.close()

    asyncio.run(scenario())


def test_classifier_failure_does_not_invent_an_answer() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app(FailingRuntime())))
        await client.start_server()
        try:
            response = await client.post("/v1/classifier", json=_payload())
            payload = await response.json()
            assert response.status == 500
            assert payload == {"message": "classification_failed"}
            assert "answers" not in payload
        finally:
            await client.close()

    asyncio.run(scenario())


def test_candidate_boundary_rejects_non_single_token_labels() -> None:
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

    runtime = server.TransformersQwenRuntime("test-model", "cpu")
    runtime._tokenizer = UnstableTokenizer()
    request = ClassifierRequest(
        model="test-model",
        state={"value": 1},
        questions={
            "route": ChoiceQuestion(
                instructions="Choose a route.",
                criteria={"a": None, "b": None},
            )
        },
    )

    with pytest.raises(RuntimeError, match="not single-token stable"):
        runtime._compile_question(request, "route")


def test_device_selection_is_explicit() -> None:
    assert server.parse_args(["--device", "cuda"]).device == "cuda"
    assert server.parse_args(["--device", "cpu"]).device == "cpu"
