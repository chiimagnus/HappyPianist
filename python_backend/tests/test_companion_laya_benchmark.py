from __future__ import annotations

import json

from python_backend.scripts.companion_laya_benchmark import (
    canonical_json_sha256,
    evaluate_stage_a,
    percentile,
    summarize,
)


def _rows(distributions: dict[str, list[str]]) -> list[dict]:
    rows: list[dict] = []
    for state, actions in distributions.items():
        for index, action in enumerate(actions):
            rows.append(
                {
                    "case_id": f"{state}-{index}",
                    "state": state,
                    "action": action,
                    "confidence": 0.7,
                    "server_latency_ms": 20 + index,
                    "round_trip_latency_ms": 30 + index,
                }
            )
    return rows


def test_canonical_json_sha_is_independent_of_formatting_and_key_order() -> None:
    left = {"b": [2, 3], "a": {"x": 1}}
    right = json.loads('{\n  "a": {"x": 1},\n  "b": [2, 3]\n}')

    assert canonical_json_sha256(left) == canonical_json_sha256(right)


def test_percentile_uses_nearest_rank() -> None:
    assert percentile([1, 2, 3, 4, 5], 0.95) == 5
    assert percentile([10, 20], 0.5) == 10


def test_stage_a_gate_rejects_single_action_collapse() -> None:
    rows = _rows(
        {
            "active_dense": ["listen"] * 20,
            "active_sparse": ["listen"] * 20,
            "natural_silence": ["listen"] * 20,
            "settled_end": ["listen"] * 20,
            "sustain_pause": ["listen"] * 20,
            "takeover_overlay": ["listen"] * 20,
        }
    )

    failures = evaluate_stage_a(summarize(rows))

    assert any("global action collapse" in failure for failure in failures)
    assert any("settled_end respond" in failure for failure in failures)
    assert any("takeover_overlay does not separate" in failure for failure in failures)


def test_stage_a_gate_accepts_separated_boundary_behavior() -> None:
    rows = _rows(
        {
            "active_dense": ["listen"] * 18 + ["support"] * 2,
            "active_sparse": ["support"] * 10 + ["sparse"] * 8 + ["listen"] * 2,
            "natural_silence": ["listen"] * 8 + ["respond"] * 8 + ["support"] * 4,
            "settled_end": ["respond"] * 16 + ["listen"] * 4,
            "sustain_pause": ["listen"] * 18 + ["sparse"] * 2,
            "takeover_overlay": ["yield"] * 16 + ["listen"] * 4,
        }
    )

    assert evaluate_stage_a(summarize(rows)) == []
