from __future__ import annotations

import pytest

from python_backend.shared.companion_laya import (
    ACTION_CRITERIA,
    DEFAULT_LAYA_MODEL,
    action_answer,
    classifier_payload,
)


def test_classifier_payload_uses_one_direct_action_question() -> None:
    state = {"held_notes_count": 2, "sustain_value": 0}

    payload = classifier_payload(model=DEFAULT_LAYA_MODEL, state=state)

    assert payload["model"] == "aac6fef/laya-multilingual-mlx"
    assert payload["state"] is state
    assert set(payload["questions"]) == {"action"}
    assert payload["questions"]["action"]["type"] == "choice"
    assert set(payload["questions"]["action"]["criteria"]) == set(ACTION_CRITERIA)


def test_action_answer_returns_direct_laya_choice() -> None:
    probabilities = {
        "listen": 0.7,
        "support": 0.1,
        "sparse": 0.1,
        "yield": 0.05,
        "respond": 0.05,
    }
    response = {
        "answers": {
            "action": {
                "type": "choice",
                "choice": "listen",
                "confidence": 0.7,
                "probabilities": probabilities,
            }
        },
        "usage": {"input_tokens": 25, "output_tokens": 0},
    }

    action, confidence, decoded = action_answer(response)

    assert action == "listen"
    assert confidence == pytest.approx(0.7)
    assert decoded == probabilities


@pytest.mark.parametrize(
    "response,match",
    [
        (
            {"answers": {}, "usage": {"input_tokens": 1, "output_tokens": 1}},
            "non-zero output_tokens",
        ),
        (
            {"answers": {}, "usage": {"input_tokens": 1, "output_tokens": 0}},
            "missing the action answer",
        ),
        (
            {
                "answers": {
                    "action": {
                        "type": "choice",
                        "choice": "dance",
                        "confidence": 1.0,
                        "probabilities": {},
                    }
                },
                "usage": {"input_tokens": 1, "output_tokens": 0},
            },
            "unsupported companion action",
        ),
    ],
)
def test_action_answer_rejects_invalid_classifier_responses(response: dict, match: str) -> None:
    with pytest.raises(ValueError, match=match):
        action_answer(response)
