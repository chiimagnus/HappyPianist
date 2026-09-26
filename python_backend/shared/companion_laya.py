from __future__ import annotations

from typing import Any


DEFAULT_LAYA_MODEL = "aac6fef/laya-multilingual-mlx"
ACTION_CRITERIA: dict[str, str] = {
    "listen": (
        "The user is actively playing, holding notes, sustaining, or only taking a brief musical "
        "breath. The AI should stay silent and keep listening."
    ),
    "support": (
        "The user is still playing and the texture is sparse and stable enough for light supportive "
        "accompaniment without taking the lead."
    ),
    "sparse": (
        "The user is still active and there is only limited room for accompaniment. If the AI joins, "
        "it should contribute very few notes."
    ),
    "yield": (
        "The AI is currently playing and the user has clearly re-entered or reasserted control. "
        "The AI should stop adding future notes and yield immediately."
    ),
    "respond": (
        "The user's phrase has clearly ended: no held notes, sustain is released, and a clear gap has "
        "formed. The AI should answer the completed phrase."
    ),
}
ACTION_QUESTION = {
    "type": "choice",
    "instructions": (
        "Choose the single piano companion action that best matches the observable MIDI state. "
        "Do not infer an ending from a short breath while notes or sustain remain active."
    ),
    "criteria": ACTION_CRITERIA,
}


def classifier_payload(*, model: str, state: dict[str, Any]) -> dict[str, Any]:
    compact_state = {
        key: value
        for key, value in state.items()
        if key != "recent_notes"
    }
    return {
        "model": model,
        "state": compact_state,
        "questions": {"action": ACTION_QUESTION},
    }


def action_answer(response: dict[str, Any]) -> tuple[str, float, dict[str, float]]:
    usage = response.get("usage")
    if not isinstance(usage, dict) or usage.get("output_tokens") != 0:
        raise ValueError("Laya classifier returned non-zero output_tokens")

    answers = response.get("answers")
    if not isinstance(answers, dict) or set(answers) != {"action"}:
        raise ValueError("Laya classifier response is missing the action answer")
    answer = answers["action"]
    if not isinstance(answer, dict) or answer.get("type") != "choice":
        raise ValueError("Laya action answer is not a choice answer")

    action = answer.get("choice")
    if action not in ACTION_CRITERIA:
        raise ValueError(f"Laya returned unsupported companion action: {action!r}")

    probabilities = answer.get("probabilities")
    if not isinstance(probabilities, dict) or set(probabilities) != set(ACTION_CRITERIA):
        raise ValueError("Laya action probabilities do not match the supported actions")
    normalized = {key: float(probabilities[key]) for key in ACTION_CRITERIA}
    if any(value < 0 or value > 1 for value in normalized.values()):
        raise ValueError("Laya action probabilities are outside 0...1")
    if abs(sum(normalized.values()) - 1.0) > 1e-3:
        raise ValueError("Laya action probabilities do not sum to 1")

    confidence = float(answer.get("confidence", normalized[action]))
    if not 0 <= confidence <= 1:
        raise ValueError("Laya action confidence is outside 0...1")
    return str(action), confidence, normalized
