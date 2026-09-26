from __future__ import annotations

from typing import Any


SEMANTIC_KEYS = ("continuing", "finished", "space", "reasserted")
SEMANTIC_THRESHOLD = 0.55
SPARSE_DENSITY_THRESHOLD = 2.0
SEMANTIC_PROTOCOL_ID = "observable-binary-v2-label-swapped"
ACTION_MAPPING_ID = "semantic-v1"

SEMANTIC_INSTRUCTIONS: dict[str, str] = {
    "continuing": "Binary decision from the JSON state: is the pianist still continuing the current phrase?",
    "finished": "Binary decision from the JSON state: has the pianist clearly finished the current phrase?",
    "space": "Binary decision from the JSON state: while the pianist is still active, is there room for light accompaniment?",
    "reasserted": "Binary decision from the JSON state: while AI playback is active, has the pianist reasserted control?",
}

SEMANTIC_CRITERIA: dict[str, dict[str, str]] = {
    "continuing": {
        "true": (
            "true when held_notes_count > 0, OR sustain_value >= 64, OR "
            "seconds_since_last_note_on < 0.50."
        ),
        "false": (
            "false when held_notes_count == 0, sustain_value < 64, AND "
            "seconds_since_last_note_on >= 0.75."
        ),
    },
    "finished": {
        "true": (
            "true only when held_notes_count == 0, sustain_value < 64, AND "
            "seconds_since_last_note_on >= 0.75."
        ),
        "false": (
            "false when held_notes_count > 0, OR sustain_value >= 64, OR "
            "seconds_since_last_note_on < 0.50."
        ),
    },
    "space": {
        "true": (
            "true when the phrase is still active and recent_note_density_per_second < 2.0; "
            "a longer recent_ioi_median_seconds also supports room for light accompaniment."
        ),
        "false": (
            "false when the phrase has finished, OR recent_note_density_per_second >= 2.0 "
            "with continuous active playing."
        ),
    },
    "reasserted": {
        "true": (
            "true only when is_ai_playback_active == true AND the pianist has recent active input: "
            "held_notes_count > 0, OR seconds_since_last_note_on < 0.50, OR "
            "recent_note_density_per_second >= 2.0."
        ),
        "false": (
            "false whenever is_ai_playback_active == false. This condition is mandatory."
        ),
    },
}


def compact_companion_state(state: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in state.items() if key != "recent_notes"}


def order_balanced_questions() -> dict[str, dict[str, Any]]:
    questions: dict[str, dict[str, Any]] = {}
    for semantic in SEMANTIC_KEYS:
        criteria = SEMANTIC_CRITERIA[semantic]
        questions[f"{semantic}__true_a"] = {
            "type": "choice",
            "instructions": SEMANTIC_INSTRUCTIONS[semantic],
            "criteria": {
                "A": criteria["true"],
                "B": criteria["false"],
            },
        }
        questions[f"{semantic}__true_b"] = {
            "type": "choice",
            "instructions": SEMANTIC_INSTRUCTIONS[semantic],
            "criteria": {
                "A": criteria["false"],
                "B": criteria["true"],
            },
        }
    return questions


def classifier_payload(*, model: str, state: dict[str, Any]) -> dict[str, Any]:
    return {
        "model": model,
        "state": compact_companion_state(state),
        "questions": order_balanced_questions(),
    }


def _true_probability(
    answer: Any,
    question_id: str,
    *,
    true_label: str,
) -> float:
    if not isinstance(answer, dict) or answer.get("type") != "choice":
        raise ValueError(f"semantic answer {question_id!r} is not a choice answer")
    probabilities = answer.get("probabilities")
    if not isinstance(probabilities, dict) or set(probabilities) != {"A", "B"}:
        raise ValueError(f"semantic answer {question_id!r} is not binary")
    a_probability = float(probabilities["A"])
    b_probability = float(probabilities["B"])
    if (
        a_probability < 0
        or b_probability < 0
        or a_probability > 1
        or b_probability > 1
        or abs(a_probability + b_probability - 1.0) > 1e-4
    ):
        raise ValueError(f"semantic answer {question_id!r} has invalid probabilities")
    return float(probabilities[true_label])


def semantic_scores(response: dict[str, Any]) -> dict[str, float]:
    usage = response.get("usage")
    if not isinstance(usage, dict) or usage.get("output_tokens") != 0:
        raise ValueError("classifier returned non-zero output_tokens")
    answers = response.get("answers")
    expected = set(order_balanced_questions())
    if not isinstance(answers, dict) or set(answers) != expected:
        raise ValueError("classifier response does not contain the expected semantic answers")

    scores: dict[str, float] = {}
    for semantic in SEMANTIC_KEYS:
        true_on_a = _true_probability(
            answers[f"{semantic}__true_a"],
            f"{semantic}__true_a",
            true_label="A",
        )
        true_on_b = _true_probability(
            answers[f"{semantic}__true_b"],
            f"{semantic}__true_b",
            true_label="B",
        )
        scores[semantic] = (true_on_a + true_on_b) / 2.0
    return scores


def semantic_order_gaps(response: dict[str, Any]) -> dict[str, float]:
    answers = response.get("answers")
    expected = set(order_balanced_questions())
    if not isinstance(answers, dict) or set(answers) != expected:
        raise ValueError("classifier response does not contain the expected semantic answers")

    return {
        semantic: abs(
            _true_probability(
                answers[f"{semantic}__true_a"],
                f"{semantic}__true_a",
                true_label="A",
            )
            - _true_probability(
                answers[f"{semantic}__true_b"],
                f"{semantic}__true_b",
                true_label="B",
            )
        )
        for semantic in SEMANTIC_KEYS
    }


def action_from_semantics(
    state: dict[str, Any],
    scores: dict[str, float],
    *,
    threshold: float = SEMANTIC_THRESHOLD,
) -> str:
    continuing = scores["continuing"]
    finished = scores["finished"]
    space = scores["space"]
    reasserted = scores["reasserted"]

    if bool(state.get("is_ai_playback_active")) and reasserted >= threshold:
        return "yield"
    if finished >= threshold and continuing < threshold:
        return "respond"
    if continuing < threshold:
        return "listen"
    if space < threshold:
        return "listen"

    density = float(state.get("recent_note_density_per_second", 0.0))
    return "sparse" if density >= SPARSE_DENSITY_THRESHOLD else "support"


def action_mapping_metadata() -> dict[str, Any]:
    return {
        "id": ACTION_MAPPING_ID,
        "semantic_protocol_id": SEMANTIC_PROTOCOL_ID,
        "semantic_threshold": SEMANTIC_THRESHOLD,
        "sparse_density_threshold": SPARSE_DENSITY_THRESHOLD,
        "priority": ["yield", "respond", "listen", "support_or_sparse"],
        "binary_ordering": ["true_on_A", "true_on_B"],
        "order_aggregation": "mean_semantic_true_probability_after_label_alignment",
    }
