from __future__ import annotations

import json

from python_backend.scripts.companion_semantic_benchmark import (
    canonical_json_sha256,
    screening_diagnostics,
    summarize,
)
from python_backend.shared.companion_semantics import (
    SEMANTIC_KEYS,
    action_from_semantics,
    classifier_payload,
    order_balanced_questions,
    semantic_order_gaps,
    semantic_scores,
)


def test_binary_questions_are_order_balanced_with_identical_semantics() -> None:
    questions = order_balanced_questions()
    assert set(questions) == {
        f"{semantic}__{order}"
        for semantic in SEMANTIC_KEYS
        for order in ("false_true", "true_false")
    }
    for semantic in SEMANTIC_KEYS:
        forward = questions[f"{semantic}__false_true"]
        reverse = questions[f"{semantic}__true_false"]
        assert list(forward["criteria"]) == ["false", "true"]
        assert list(reverse["criteria"]) == ["true", "false"]
        assert forward["criteria"] == reverse["criteria"]
        assert forward["instructions"] == reverse["instructions"]


def test_semantic_scores_align_labels_before_averaging_orders() -> None:
    answers = {}
    for semantic in SEMANTIC_KEYS:
        answers[f"{semantic}__false_true"] = {
            "type": "choice",
            "choice": "true",
            "probabilities": {"false": 0.2, "true": 0.8},
        }
        answers[f"{semantic}__true_false"] = {
            "type": "choice",
            "choice": "false",
            "probabilities": {"true": 0.4, "false": 0.6},
        }
    response = {
        "answers": answers,
        "usage": {"input_tokens": 10, "output_tokens": 0},
    }

    scores = semantic_scores(response)
    for value in scores.values():
        assert abs(value - 0.6) < 1e-12
    gaps = semantic_order_gaps(response)
    for value in gaps.values():
        assert abs(value - 0.4) < 1e-12


def test_classifier_payload_removes_recent_notes_and_keeps_same_state_for_all_backends() -> None:
    payload = classifier_payload(
        model="backend-model",
        state={
            "held_notes_count": 1,
            "sustain_value": 0,
            "recent_notes": [{"midi": 60}],
        },
    )

    assert payload["model"] == "backend-model"
    assert payload["state"] == {"held_notes_count": 1, "sustain_value": 0}
    assert len(payload["questions"]) == 8


def test_action_mapping_matches_original_semantic_v1_priority() -> None:
    base = {"is_ai_playback_active": False, "recent_note_density_per_second": 1.0}
    neutral = {semantic: 0.5 for semantic in SEMANTIC_KEYS}

    assert action_from_semantics(
        {**base, "is_ai_playback_active": True},
        {**neutral, "reasserted": 0.55},
    ) == "yield"
    assert action_from_semantics(
        base,
        {**neutral, "continuing": 0.4, "finished": 0.55},
    ) == "respond"
    assert action_from_semantics(
        base,
        {**neutral, "continuing": 0.9, "finished": 0.1, "space": 0.4},
    ) == "listen"
    assert action_from_semantics(
        base,
        {**neutral, "continuing": 0.9, "finished": 0.1, "space": 0.9},
    ) == "support"
    assert action_from_semantics(
        {**base, "recent_note_density_per_second": 2.0},
        {**neutral, "continuing": 0.9, "finished": 0.1, "space": 0.9},
    ) == "sparse"


def _row(state: str, source: str, action: str, semantics: dict[str, float]) -> dict:
    return {
        "case_id": f"{source}-{state}-{action}",
        "source": source,
        "state": state,
        "action": action,
        "semantic_scores": semantics,
        "semantic_order_gaps": {semantic: 0.02 for semantic in SEMANTIC_KEYS},
        "server_latency_ms": 20.0,
        "round_trip_latency_ms": 30.0,
    }


def test_screening_accepts_expected_semantic_boundaries() -> None:
    state_semantics = {
        "active_dense": {"continuing": 0.8, "finished": 0.2, "space": 0.2, "reasserted": 0.2},
        "active_sparse": {"continuing": 0.8, "finished": 0.2, "space": 0.8, "reasserted": 0.2},
        "natural_silence": {"continuing": 0.4, "finished": 0.4, "space": 0.2, "reasserted": 0.2},
        "settled_end": {"continuing": 0.2, "finished": 0.8, "space": 0.2, "reasserted": 0.2},
        "sustain_pause": {"continuing": 0.8, "finished": 0.2, "space": 0.5, "reasserted": 0.2},
        "takeover_overlay": {"continuing": 0.8, "finished": 0.2, "space": 0.2, "reasserted": 0.8},
    }
    actions = {
        "active_dense": "listen",
        "active_sparse": "support",
        "natural_silence": "listen",
        "settled_end": "respond",
        "sustain_pause": "listen",
        "takeover_overlay": "yield",
    }
    rows = []
    for source in ("maestro", "pop909"):
        for state, semantics in state_semantics.items():
            for _ in range(10):
                rows.append(_row(state, source, actions[state], semantics))

    diagnostics = screening_diagnostics(summarize(rows))

    assert diagnostics["passed"] is True
    assert diagnostics["automatic_stop_reasons"] == []


def test_screening_rejects_semantic_collapse() -> None:
    collapsed = {semantic: 0.2 for semantic in SEMANTIC_KEYS}
    rows = []
    for source in ("maestro", "pop909"):
        for state in (
            "active_dense",
            "active_sparse",
            "natural_silence",
            "settled_end",
            "sustain_pause",
            "takeover_overlay",
        ):
            for _ in range(10):
                rows.append(_row(state, source, "listen", collapsed))

    diagnostics = screening_diagnostics(summarize(rows))

    assert diagnostics["passed"] is False
    assert any(reason.startswith("action_collapse") for reason in diagnostics["automatic_stop_reasons"])
    assert any("settled_end:finished" in reason for reason in diagnostics["automatic_stop_reasons"])


def test_canonical_json_sha_is_format_independent() -> None:
    left = {"b": [2, 3], "a": {"x": 1}}
    right = json.loads('{\n  "a": {"x": 1},\n  "b": [2, 3]\n}')
    assert canonical_json_sha256(left) == canonical_json_sha256(right)
