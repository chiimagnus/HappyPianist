from __future__ import annotations

import asyncio
from typing import Any

import pytest
from aiohttp.test_utils import TestClient, TestServer
from pydantic import ValidationError

from jev_server import server
from shared.jev_protocol import (
    ChoiceAnswer,
    ChoiceQuestion,
    ClassifierRequest,
    ClassifierResponse,
    ClassifierUsage,
    NoulQuestion,
    build_choice_prompt,
    build_noul_prompt,
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
                    probabilities={
                        "billing": 0.8,
                        "technical": 0.2,
                    },
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

    plan = build_choice_prompt(
        request.state,
        request.questions,
        "route",
    )

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


def test_noul_prompt_uses_numeric_answer_boundary() -> None:
    request = ClassifierRequest(
        model="Qwen/Qwen3.5-0.8B",
        state={"signal": "strong"},
        questions={
            "supported": NoulQuestion(
                instructions="Is the proposition supported?",
                criteria={"true": "Evidence supports it.", "false": "Evidence contradicts it."},
            )
        },
    )

    plan = build_noul_prompt(request.state, request.questions, "supported")

    assert plan.labels == list("123456789")
    assert plan.answer_prefix == '{"answer": '
    assert "0.1" in plan.messages[1]["content"]
    assert "supported" in plan.messages[1]["content"].lower()
    assert "ordered 0/1" not in plan.messages[0]["content"]
    assert "larger numbers mean stronger support" in plan.messages[0]["content"]


def test_noul_question_rejects_unknown_truth_criteria() -> None:
    with pytest.raises(ValidationError):
        NoulQuestion(
            instructions="Is this true?",
            criteria={"maybe": "Unknown."},
        )


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


def test_choice_question_rejects_non_decision_candidate_counts() -> None:
    with pytest.raises(ValidationError):
        ChoiceQuestion(
            instructions="Choose.",
            criteria={"only": None},
        )

    with pytest.raises(ValidationError):
        ChoiceQuestion(
            instructions="Choose.",
            criteria={f"candidate-{index}": None for index in range(51)},
        )



def test_shared_prefix_keeps_question_specific_suffix() -> None:
    compiled = [
        server.CompiledQuestion(
            question_id="a",
            question_type="noul",
            token_ids=[1, 2, 3, 4, 5],
            candidate_ids=[10],
            choices=["1"],
        ),
        server.CompiledQuestion(
            question_id="b",
            question_type="noul",
            token_ids=[1, 2, 3, 8, 9],
            candidate_ids=[10],
            choices=["1"],
        ),
    ]

    assert server.TransformersJevRuntime._common_prefix_length(compiled) == 3


def test_shared_prefix_does_not_consume_entire_shortest_prompt() -> None:
    compiled = [
        server.CompiledQuestion(
            question_id="a",
            question_type="noul",
            token_ids=[1, 2, 3],
            candidate_ids=[10],
            choices=["1"],
        ),
        server.CompiledQuestion(
            question_id="b",
            question_type="noul",
            token_ids=[1, 2, 3, 4],
            candidate_ids=[10],
            choices=["1"],
        ),
    ]

    assert server.TransformersJevRuntime._common_prefix_length(compiled) == 2


def test_device_selection_is_explicit() -> None:
    assert server.parse_args(["--device", "cuda"]).device == "cuda"
    assert server.parse_args(["--device", "cpu"]).device == "cpu"
