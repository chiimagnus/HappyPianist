#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import itertools
import json
import math
from pathlib import Path
import statistics
import sys
import time
from typing import Any

PYTHON_BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(PYTHON_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(PYTHON_BACKEND_ROOT))

from scripts.companion_e2e_acceptance import (
    decision_payload,
    load_midi,
    post_json,
    resolve_under_python_backend,
    sample_scenarios,
    scenario_path,
)
from shared.companion_semantics import (
    SEMANTIC_KEYS,
    SEMANTIC_THRESHOLD,
    action_from_semantics,
    action_mapping_metadata,
    classifier_payload,
    semantic_order_gaps,
    semantic_scores,
)


DEFAULT_STATES = (
    "active_dense",
    "active_sparse",
    "natural_silence",
    "settled_end",
    "sustain_pause",
    "takeover_overlay",
)
ACTION_COLLAPSE_SHARE = 0.90
CROSS_SOURCE_DIRECTION_GAP = 0.15
LATENCY_HARD_LIMIT_MS = 1000.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--corpus-index",
        type=Path,
        default=Path(".outputs/companion-corpus/index.json"),
    )
    parser.add_argument(
        "--maestro-root",
        type=Path,
        default=Path(".datasets/maestro-v3/extracted/maestro-v3.0.0"),
    )
    parser.add_argument(
        "--pop909-root",
        type=Path,
        default=Path(".datasets/pop909/extracted/POP909"),
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8767)
    parser.add_argument("--model", required=True)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--seed", type=int, default=20260920)
    parser.add_argument("--cases-per-state-per-source", type=int, default=10)
    parser.add_argument("--prompt-window", type=float, default=3.0)
    parser.add_argument("--states", default=",".join(DEFAULT_STATES))
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(".outputs/companion-semantic-benchmark/results.json"),
    )
    parser.add_argument(
        "--no-gate",
        action="store_true",
        help="Record evidence without failing the process when Stage A invariants fail.",
    )
    return parser.parse_args()


def canonical_json_sha256(payload: Any) -> str:
    canonical = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def percentile(values: list[float], percentile_value: float) -> float:
    if not values:
        raise ValueError("percentile requires at least one value")
    ordered = sorted(values)
    index = max(0, math.ceil(percentile_value * len(ordered)) - 1)
    return ordered[index]


def median_semantics(rows: list[dict[str, Any]]) -> dict[str, float]:
    if not rows:
        raise ValueError("semantic median requires rows")
    return {
        semantic: statistics.median(
            float(row["semantic_scores"][semantic]) for row in rows
        )
        for semantic in SEMANTIC_KEYS
    }


def median_order_gaps(rows: list[dict[str, Any]]) -> dict[str, float]:
    if not rows:
        raise ValueError("order-gap median requires rows")
    return {
        semantic: statistics.median(
            float(row["semantic_order_gaps"][semantic]) for row in rows
        )
        for semantic in SEMANTIC_KEYS
    }


def summarize(rows: list[dict[str, Any]]) -> dict[str, Any]:
    if not rows:
        raise ValueError("benchmark produced no rows")
    states = sorted({str(row["state"]) for row in rows})
    sources = sorted({str(row["source"]) for row in rows})
    actions = Counter(str(row["action"]) for row in rows)
    actions_by_state = {
        state: dict(Counter(str(row["action"]) for row in rows if row["state"] == state))
        for state in states
    }
    semantics_by_state = {
        state: median_semantics([row for row in rows if row["state"] == state])
        for state in states
    }
    order_gap_by_state = {
        state: median_order_gaps([row for row in rows if row["state"] == state])
        for state in states
    }
    semantics_by_source_state: dict[str, dict[str, dict[str, float]]] = {}
    for source in sources:
        semantics_by_source_state[source] = {}
        source_rows = [row for row in rows if row["source"] == source]
        for state in states:
            state_rows = [row for row in source_rows if row["state"] == state]
            if state_rows:
                semantics_by_source_state[source][state] = median_semantics(state_rows)

    server_latencies = [float(row["server_latency_ms"]) for row in rows]
    round_trip_latencies = [float(row["round_trip_latency_ms"]) for row in rows]
    return {
        "cases": len(rows),
        "sources": sources,
        "states": states,
        "actions": dict(actions),
        "actions_by_state": actions_by_state,
        "semantic_medians_by_state": semantics_by_state,
        "semantic_medians_by_source_state": semantics_by_source_state,
        "semantic_order_gap_medians_by_state": order_gap_by_state,
        "server_latency_ms": {
            "median": statistics.median(server_latencies),
            "p95": percentile(server_latencies, 0.95),
            "max": max(server_latencies),
        },
        "round_trip_latency_ms": {
            "median": statistics.median(round_trip_latencies),
            "p95": percentile(round_trip_latencies, 0.95),
            "max": max(round_trip_latencies),
        },
    }


def action_rate(summary: dict[str, Any], state: str, action: str) -> float:
    counts = summary["actions_by_state"][state]
    total = sum(int(count) for count in counts.values())
    return float(counts.get(action, 0)) / total if total else 0.0


def cross_source_direction_conflicts(summary: dict[str, Any]) -> list[dict[str, Any]]:
    by_source = summary["semantic_medians_by_source_state"]
    conflicts: list[dict[str, Any]] = []
    for left, right in itertools.combinations(summary["sources"], 2):
        for state in summary["states"]:
            if state not in by_source[left] or state not in by_source[right]:
                continue
            for semantic in SEMANTIC_KEYS:
                left_value = float(by_source[left][state][semantic])
                right_value = float(by_source[right][state][semantic])
                crosses = (left_value - 0.5) * (right_value - 0.5) < 0
                if crosses and abs(left_value - right_value) >= CROSS_SOURCE_DIRECTION_GAP:
                    conflicts.append(
                        {
                            "sources": [left, right],
                            "state": state,
                            "semantic": semantic,
                            "values": {left: left_value, right: right_value},
                        }
                    )
    return conflicts


def screening_diagnostics(summary: dict[str, Any]) -> dict[str, Any]:
    medians = summary["semantic_medians_by_state"]
    reasons: list[str] = []

    action_total = sum(int(value) for value in summary["actions"].values())
    dominant_action, dominant_count = max(
        summary["actions"].items(), key=lambda item: int(item[1])
    )
    dominant_share = int(dominant_count) / action_total
    if dominant_share >= ACTION_COLLAPSE_SHARE:
        reasons.append(f"action_collapse:{dominant_action}:{dominant_share:.3f}")

    expected = {
        ("active_dense", "continuing"): True,
        ("active_dense", "finished"): False,
        ("active_dense", "space"): False,
        ("active_dense", "reasserted"): False,
        ("active_sparse", "continuing"): True,
        ("active_sparse", "finished"): False,
        ("active_sparse", "space"): True,
        ("settled_end", "continuing"): False,
        ("settled_end", "finished"): True,
        ("sustain_pause", "continuing"): True,
        ("sustain_pause", "finished"): False,
        ("takeover_overlay", "reasserted"): True,
    }
    for (state, semantic), should_be_true in expected.items():
        value = float(medians[state][semantic])
        observed_true = value >= SEMANTIC_THRESHOLD
        if observed_true != should_be_true:
            reasons.append(
                f"semantic_boundary:{state}:{semantic}:{value:.3f}:expected_"
                f"{'true' if should_be_true else 'false'}"
            )

    if action_rate(summary, "active_dense", "respond") >= 0.25:
        reasons.append("active_dense_respond_rate_too_high")
    if action_rate(summary, "settled_end", "respond") <= action_rate(
        summary, "active_dense", "respond"
    ):
        reasons.append("settled_end_not_above_active_dense_on_respond")
    if action_rate(summary, "takeover_overlay", "yield") <= action_rate(
        summary, "active_dense", "yield"
    ):
        reasons.append("takeover_overlay_not_above_active_dense_on_yield")
    if float(summary["round_trip_latency_ms"]["p95"]) >= LATENCY_HARD_LIMIT_MS:
        reasons.append(
            f"latency_p95:{float(summary['round_trip_latency_ms']['p95']):.1f}ms"
        )

    source_conflicts = cross_source_direction_conflicts(summary)
    if source_conflicts:
        reasons.append(f"cross_source_direction_conflicts:{len(source_conflicts)}")

    return {
        "dominant_action": {
            "action": dominant_action,
            "share": dominant_share,
        },
        "semantic_threshold": SEMANTIC_THRESHOLD,
        "cross_source_direction_conflicts": source_conflicts,
        "automatic_stop_reasons": reasons,
        "passed": not reasons,
    }


def main() -> int:
    args = parse_args()
    index_path = resolve_under_python_backend(args.corpus_index)
    maestro_root = resolve_under_python_backend(args.maestro_root)
    pop909_root = resolve_under_python_backend(args.pop909_root)
    output = resolve_under_python_backend(args.output)

    raw_index = index_path.read_bytes()
    corpus_index = json.loads(raw_index)
    states = {state.strip() for state in args.states.split(",") if state.strip()}
    scenarios = sample_scenarios(
        corpus_index,
        states=states,
        cases_per_state_per_source=args.cases_per_state_per_source,
        seed=args.seed,
    )

    url = f"http://{args.host}:{args.port}/v1/classifier"
    midi_cache: dict[Path, Any] = {}
    rows: list[dict[str, Any]] = []
    for scenario in scenarios:
        path = scenario_path(
            scenario,
            maestro_root=maestro_root,
            pop909_root=pop909_root,
        )
        parsed = midi_cache.get(path)
        if parsed is None:
            parsed = load_midi(path)
            midi_cache[path] = parsed
        state = decision_payload(parsed, scenario, args.prompt_window)
        request = classifier_payload(model=args.model, state=state)
        started = time.perf_counter()
        response = post_json(url, request, args.timeout)
        round_trip_latency_ms = (time.perf_counter() - started) * 1000
        scores = semantic_scores(response)
        order_gaps = semantic_order_gaps(response)
        rows.append(
            {
                "case_id": scenario.case_id,
                "source": scenario.source,
                "state": scenario.name,
                "semantic_scores": scores,
                "semantic_order_gaps": order_gaps,
                "action": action_from_semantics(state, scores),
                "server_latency_ms": float(response["latency_ms"]),
                "round_trip_latency_ms": round_trip_latency_ms,
            }
        )

    summary = summarize(rows)
    screening = screening_diagnostics(summary)
    payload = {
        "methodology_note": (
            "Model-agnostic semantic-v1 benchmark: the backend answers the same four binary "
            "questions in both option orders; true probabilities are aligned and averaged before "
            "the same deterministic action mapping is applied."
        ),
        "model": args.model,
        "seed": args.seed,
        "cases_per_state_per_source": args.cases_per_state_per_source,
        "states": sorted(states),
        "corpus_index_sha256_raw": hashlib.sha256(raw_index).hexdigest(),
        "corpus_index_sha256_canonical": canonical_json_sha256(corpus_index),
        "case_ids": [row["case_id"] for row in rows],
        "action_mapping": action_mapping_metadata(),
        "summary": summary,
        "screening": screening,
        "cases": rows,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
        newline="\n",
    )
    print(
        json.dumps(
            {"summary": summary, "screening": screening},
            ensure_ascii=False,
            indent=2,
        )
    )
    if not screening["passed"] and not args.no_gate:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
