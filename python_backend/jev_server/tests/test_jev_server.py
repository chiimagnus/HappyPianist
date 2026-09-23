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


def test_shared_system_question_order_is_deterministic() -> None:
    route = ChoiceQuestion(
        instructions="Choose a route.",
        criteria={"billing": None, "technical": None},
    )
    urgency = NoulQuestion(instructions="Is this urgent?")
    state = {"message": "hello"}

    first = build_choice_prompt(
        state,
        {"route": route, "urgency": urgency},
        "route",
    )
    reversed_order = build_choice_prompt(
        state,
        {"urgency": urgency, "route": route},
        "route",
    )

    assert first.messages == reversed_order.messages


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



def test_noul_scoring_returns_complete_distribution_and_expected_probability() -> None:
    import torch

    class TokenizerStub:
        pad_token_id = 0
        eos_token_id = 0

    class NoulScoringRuntime(server.TransformersJevRuntime):
        def __init__(self) -> None:
            super().__init__("test-model", "cpu")
            self._model = object()
            self._tokenizer = TokenizerStub()

        def _compile_question(
            self,
            request: ClassifierRequest,
            question_id: str,
        ) -> server.CompiledQuestion:
            assert isinstance(request.questions[question_id], NoulQuestion)
            return server.CompiledQuestion(
                question_id=question_id,
                question_type="noul",
                token_ids=[1, 2, 3],
                candidate_ids=list(range(9)),
                choices=list("123456789"),
            )

        def _forward_full(
            self,
            compiled: list[server.CompiledQuestion],
            torch_module: Any,
            pad_token_id: int,
        ) -> list[Any]:
            assert len(compiled) == 1
            assert pad_token_id == 0
            return [torch_module.zeros(9)]

    response = NoulScoringRuntime().classify(
        ClassifierRequest(
            model="test-model",
            state={"signal": "neutral"},
            questions={
                "supported": NoulQuestion(
                    instructions="Is the proposition supported?"
                )
            },
        )
    )
    answer = response.answers["supported"]
    assert answer.type == "noul"
    assert set(answer.rating.probabilities) == set("123456789")
    assert sum(answer.rating.probabilities.values()) == pytest.approx(1.0)
    assert answer.rating.expected_score == pytest.approx(5.0)
    assert answer.noul == pytest.approx(0.5)
    assert 0.1 <= answer.noul <= 0.9
    assert response.usage.output_tokens == 0


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

    runtime = server.TransformersJevRuntime("test-model", "cpu")
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
