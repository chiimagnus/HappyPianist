from __future__ import annotations

import asyncio
from typing import Any

import pytest
from aiohttp.test_utils import TestClient, TestServer
from pydantic import ValidationError

from laya_server import server
from shared.laya_protocol import (
    ActionTrace,
    ChoiceAnswer,
    ChoiceQuestion,
    ClassifierRequest,
    ClassifierResponse,
    ClassifierUsage,
    NoulQuestion,
    ScoreQuestion,
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
                    action=ActionTrace(act_probability=0.6),
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
        model=server.DEFAULT_MODEL,
    )


def _payload() -> dict[str, Any]:
    return {
        "model": server.DEFAULT_MODEL,
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


def test_protocol_accepts_laya_choice_score_and_noul_questions() -> None:
    request = ClassifierRequest(
        model=server.DEFAULT_MODEL,
        state={"signal": "mixed"},
        questions={
            "route": ChoiceQuestion(
                instructions="Choose a route.",
                criteria={"billing": "money", "technical": "bug"},
            ),
            "urgency": ScoreQuestion(
                instructions="Rate urgency.",
                criteria=["low", "medium", "high"],
            ),
            "refund": NoulQuestion(
                instructions="Is a refund requested?",
                criteria={"false": "no refund", "true": "refund requested"},
            ),
        },
    )

    assert set(request.questions) == {"route", "urgency", "refund"}


def test_protocol_does_not_keep_old_jev_candidate_count_limits() -> None:
    assert ChoiceQuestion(instructions="Choose.", criteria=["only"]).criteria == ["only"]
    assert len(
        ChoiceQuestion(
            instructions="Choose.",
            criteria=[f"candidate-{index}" for index in range(51)],
        ).criteria
    ) == 51
    assert ScoreQuestion(instructions="Score.", criteria=["only"]).criteria == ["only"]

    with pytest.raises(ValidationError):
        ChoiceQuestion(instructions="Choose.", criteria=["same", "same"])


def test_noul_question_rejects_unknown_truth_criteria() -> None:
    with pytest.raises(ValidationError):
        NoulQuestion(
            instructions="Is this true?",
            criteria={"maybe": "Unknown."},
        )


def test_classifier_endpoint_returns_laya_typed_choice_without_output_tokens() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app(FixedRuntime())))
        await client.start_server()
        try:
            response = await client.post("/v1/classifier", json=_payload())
            payload = await response.json()

            assert response.status == 200
            assert payload["model"] == server.DEFAULT_MODEL
            assert payload["answers"]["route"]["type"] == "choice"
            assert payload["answers"]["route"]["choice"] == "billing"
            assert payload["answers"]["route"]["probabilities"]["billing"] == 0.8
            assert payload["answers"]["route"]["action"]["act_probability"] == 0.6
            assert payload["usage"]["output_tokens"] == 0
            assert payload["latency_ms"] == 11
        finally:
            await client.close()

    asyncio.run(scenario())


def test_classifier_rejects_model_mismatch_before_inference() -> None:
    async def scenario() -> None:
        client = TestClient(TestServer(_test_app(FailingRuntime())))
        await client.start_server()
        try:
            payload = _payload()
            payload["model"] = "some-other-model"
            response = await client.post("/v1/classifier", json=payload)
            body = await response.json()

            assert response.status == 400
            assert "does not match" in body["message"]
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


def test_laya_runtime_passes_state_and_questions_through_without_scoring_reimplementation() -> None:
    class AgentStub:
        def __init__(self) -> None:
            self.calls: list[tuple[Any, dict[str, Any]]] = []

        def predict(self, state: Any, questions: dict[str, Any]) -> dict[str, Any]:
            self.calls.append((state, questions))
            return {
                "model": "laya-rl-agent",
                "answers": {
                    "route": {
                        "type": "choice",
                        "confidence": 0.75,
                        "action": {"act_probability": 0.55},
                        "choice": "billing",
                        "probabilities": {"billing": 0.75, "technical": 0.25},
                    }
                },
                "usage": {"input_tokens": 17, "output_tokens": 0},
            }

    runtime = server.LayaRuntime(server.DEFAULT_MODEL)
    agent = AgentStub()
    runtime._agent = agent
    request = ClassifierRequest.model_validate(_payload())

    response = runtime.classify(request)

    assert response.model == server.DEFAULT_MODEL
    assert response.usage.output_tokens == 0
    assert response.answers["route"].choice == "billing"
    assert agent.calls == [
        (
            request.state,
            {
                "route": {
                    "type": "choice",
                    "instructions": "Which team should handle this request?",
                    "criteria": {
                        "billing": "Payments, invoices, and refunds.",
                        "technical": "Product errors and technical failures.",
                    },
                }
            },
        )
    ]


def test_runtime_rejects_nonzero_output_tokens() -> None:
    class AgentStub:
        def predict(self, _: Any, __: dict[str, Any]) -> dict[str, Any]:
            return {
                "answers": {},
                "usage": {"input_tokens": 0, "output_tokens": 1},
            }

    runtime = server.LayaRuntime(server.DEFAULT_MODEL)
    runtime._agent = AgentStub()

    with pytest.raises(RuntimeError, match="zero-output-token"):
        runtime.classify(ClassifierRequest.model_validate(_payload()))


def test_default_model_is_small_multilingual_mlx_checkpoint() -> None:
    assert server.parse_args([]).model == "aac6fef/laya-multilingual-mlx"
