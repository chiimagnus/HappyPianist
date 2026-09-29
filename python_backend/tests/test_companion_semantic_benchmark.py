from __future__ import annotations

import json

import pytest
from pydantic import ValidationError

from python_backend.scripts.companion_semantic_benchmark import (
    MANIFEST_PATH,
    canonical_json_sha256,
    case_ids_sha256,
    load_manifest,
    screening_diagnostics,
    summarize,
)
from python_backend.shared.companion_semantics import (
    SEMANTIC_KEYS,
    action_from_semantics,
    aggregate_semantics,
    build_semantic_prompt,
    semantic_question_ids,
)
from python_backend.shared.qwen_companion_protocol import companion_state_payload


def _qwen_state() -> dict:
    return {
        "held_notes_count": 1,
        "sustain_value": 0,
        "recent_ioi_median_seconds": 0.42,
        "recent_note_density_per_second": 1.0,
        "seconds_since_last_note_on": 0.1,
        "is_ai_playback_active": False,
        "user_note_on_since_ai_playback_started": False,
    }


def test_binary_questions_are_fixed_ab_and_order_balanced() -> None:
    assert set(semantic_question_ids()) == {
        f"{semantic}__{variant}"
        for semantic in SEMANTIC_KEYS
        for variant in ("true_a", "true_b")
    }
    for semantic in SEMANTIC_KEYS:
        true_a = build_semantic_prompt(_qwen_state(), f"{semantic}__true_a")
        true_b = build_semantic_prompt(_qwen_state(), f"{semantic}__true_b")
        assert true_a.labels == ["A", "B"]
        assert true_b.labels == ["A", "B"]
        assert true_a.messages[1]["content"] != true_b.messages[1]["content"]


def test_semantic_scores_align_labels_before_averaging_orders() -> None:
    probabilities = {}
    for semantic in SEMANTIC_KEYS:
        probabilities[f"{semantic}__true_a"] = {"A": 0.8, "B": 0.2}
        probabilities[f"{semantic}__true_b"] = {"A": 0.6, "B": 0.4}

    scores, gaps = aggregate_semantics(probabilities)
    for value in scores.values():
        assert abs(value - 0.6) < 1e-12
    for value in gaps.values():
        assert abs(value - 0.4) < 1e-12


def test_qwen_state_payload_rejects_unknown_legacy_fields() -> None:
    assert companion_state_payload(_qwen_state()) == _qwen_state()
    with pytest.raises(ValidationError):
        companion_state_payload({**_qwen_state(), "unexpected_legacy_field": True})


def test_action_mapping_matches_semantic_v1_priority_and_reassertion_guard() -> None:
    base = _qwen_state()
    neutral = {semantic: 0.5 for semantic in SEMANTIC_KEYS}

    assert action_from_semantics(
        {
            **base,
            "is_ai_playback_active": True,
            "user_note_on_since_ai_playback_started": True,
        },
        {**neutral, "reasserted": 0.55},
    ) == "yield"
    assert action_from_semantics(
        {**base, "is_ai_playback_active": True},
        {**neutral, "reasserted": 0.9},
    ) != "yield"
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
        "natural_silence": "listen",
        "settled_end": "respond",
        "sustain_pause": "listen",
        "takeover_overlay": "yield",
    }
    rows = []
    for source in ("maestro", "pop909"):
        for state, semantics in state_semantics.items():
            for index in range(10):
                action = (
                    ("support" if index < 5 else "sparse")
                    if state == "active_sparse"
                    else actions[state]
                )
                rows.append(_row(state, source, action, semantics))

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


def test_screening_checks_observable_boundaries_per_source() -> None:
    good = {
        "active_dense": {"continuing": 0.8, "finished": 0.2, "space": 0.2, "reasserted": 0.2},
        "active_sparse": {"continuing": 0.8, "finished": 0.2, "space": 0.8, "reasserted": 0.2},
        "natural_silence": {"continuing": 0.4, "finished": 0.4, "space": 0.2, "reasserted": 0.2},
        "settled_end": {"continuing": 0.2, "finished": 0.8, "space": 0.2, "reasserted": 0.2},
        "sustain_pause": {"continuing": 0.8, "finished": 0.2, "space": 0.5, "reasserted": 0.2},
        "takeover_overlay": {"continuing": 0.8, "finished": 0.2, "space": 0.2, "reasserted": 0.8},
    }
    rows = []
    for source in ("maestro", "pop909"):
        for state, semantics in good.items():
            current = dict(semantics)
            if source == "pop909" and state == "active_sparse":
                current["space"] = 0.2
            for index in range(10):
                action = (
                    ("support" if index < 5 else "sparse")
                    if state == "active_sparse"
                    else {"active_dense": "listen", "natural_silence": "listen", "settled_end": "respond", "sustain_pause": "listen", "takeover_overlay": "yield"}[state]
                )
                rows.append(_row(state, source, action, current))

    diagnostics = screening_diagnostics(summarize(rows))
    assert diagnostics["passed"] is False
    assert any(
        reason.startswith("semantic_boundary:pop909:active_sparse:space")
        for reason in diagnostics["automatic_stop_reasons"]
    )


def test_stage_a_manifest_has_fixed_120_case_identity() -> None:
    manifest = load_manifest()
    assert MANIFEST_PATH.exists()
    assert manifest["version"] == "companion-stage-a-v3-product-event-projection"
    assert manifest["projection_version"] == "duet-phrase-buffer-v1"
    assert manifest["projection_parameters"] == {
        "lookback_seconds": 4.0,
        "ioi_window_seconds": 2.4,
        "density_window_seconds": 1.2,
    }
    assert manifest["seed"] == 20260920
    assert manifest["cases_per_state_per_source"] == 10
    assert len(manifest["states"]) == 6
    assert len(manifest["case_ids"]) == 120
    assert case_ids_sha256(manifest["case_ids"]) == manifest["case_ids_sha256"]
    assert manifest["latency_hard_limit_ms"] == 100.0


def test_canonical_json_sha_is_format_independent() -> None:
    left = {"b": [2, 3], "a": {"x": 1}}
    right = json.loads('{\n  "a": {"x": 1},\n  "b": [2, 3]\n}')
    assert canonical_json_sha256(left) == canonical_json_sha256(right)
