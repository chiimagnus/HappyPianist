#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
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
from shared.companion_laya import DEFAULT_LAYA_MODEL, action_answer, classifier_payload


DEFAULT_STATES = (
    "active_dense",
    "active_sparse",
    "natural_silence",
    "settled_end",
    "sustain_pause",
    "takeover_overlay",
)
ACTIONS = ("listen", "support", "sparse", "yield", "respond")


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
    parser.add_argument("--model", default=DEFAULT_LAYA_MODEL)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--seed", type=int, default=20260920)
    parser.add_argument("--cases-per-state-per-source", type=int, default=10)
    parser.add_argument("--prompt-window", type=float, default=3.0)
    parser.add_argument(
        "--states",
        default=",".join(DEFAULT_STATES),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(".outputs/companion-laya-benchmark/results.json"),
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
    if not 0 <= percentile_value <= 1:
        raise ValueError("percentile must be between 0 and 1")
    ordered = sorted(values)
    index = max(0, math.ceil(percentile_value * len(ordered)) - 1)
    return ordered[index]


def action_distribution(rows: list[dict[str, Any]]) -> dict[str, float]:
    if not rows:
        return {action: 0.0 for action in ACTIONS}
    counts = Counter(str(row["action"]) for row in rows)
    total = len(rows)
    return {action: counts[action] / total for action in ACTIONS}


def summarize(rows: list[dict[str, Any]]) -> dict[str, Any]:
    if not rows:
        raise ValueError("benchmark produced no rows")
    by_state: dict[str, dict[str, float]] = {}
    for state in sorted({str(row["state"]) for row in rows}):
        by_state[state] = action_distribution(
            [row for row in rows if row["state"] == state]
        )

    latencies = [float(row["round_trip_latency_ms"]) for row in rows]
    server_latencies = [float(row["server_latency_ms"]) for row in rows]
    confidences = [float(row["confidence"]) for row in rows]
    return {
        "cases": len(rows),
        "actions": action_distribution(rows),
        "actions_by_state": by_state,
        "confidence": {
            "median": statistics.median(confidences),
            "p95": percentile(confidences, 0.95),
        },
        "server_latency_ms": {
            "median": statistics.median(server_latencies),
            "p95": percentile(server_latencies, 0.95),
            "max": max(server_latencies),
        },
        "round_trip_latency_ms": {
            "median": statistics.median(latencies),
            "p95": percentile(latencies, 0.95),
            "max": max(latencies),
        },
    }


def evaluate_stage_a(summary: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    overall = summary["actions"]
    by_state = summary["actions_by_state"]

    dominant_action, dominant_share = max(overall.items(), key=lambda item: item[1])
    if dominant_share > 0.80:
        failures.append(
            f"global action collapse: {dominant_action}={dominant_share:.1%} > 80%"
        )

    active_dense = by_state.get("active_dense", {})
    if active_dense.get("respond", 0.0) > 0.20:
        failures.append(
            f"active_dense respond={active_dense['respond']:.1%} > 20%"
        )

    sustain_pause = by_state.get("sustain_pause", {})
    if sustain_pause.get("respond", 0.0) > 0.20:
        failures.append(
            f"sustain_pause respond={sustain_pause['respond']:.1%} > 20%"
        )

    takeover = by_state.get("takeover_overlay", {})
    if takeover:
        yield_or_listen = takeover.get("yield", 0.0) + takeover.get("listen", 0.0)
        if yield_or_listen < 0.70:
            failures.append(
                f"takeover_overlay yield+listen={yield_or_listen:.1%} < 70%"
            )
        dense_yield = active_dense.get("yield", 0.0)
        if takeover.get("yield", 0.0) < dense_yield + 0.20:
            failures.append(
                "takeover_overlay does not separate from active_dense on yield "
                f"({takeover.get('yield', 0.0):.1%} vs {dense_yield:.1%})"
            )

    settled = by_state.get("settled_end", {})
    if settled.get("respond", 0.0) < 0.40:
        failures.append(
            f"settled_end respond={settled.get('respond', 0.0):.1%} < 40%"
        )

    sparse = by_state.get("active_sparse", {})
    if sparse and max(sparse.values()) > 0.80:
        action, share = max(sparse.items(), key=lambda item: item[1])
        failures.append(
            f"active_sparse collapsed to {action}={share:.1%} > 80%"
        )

    if summary["round_trip_latency_ms"]["p95"] >= 1000:
        failures.append(
            "round-trip p95 latency "
            f"{summary['round_trip_latency_ms']['p95']:.1f}ms >= 1000ms"
        )
    return failures


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
        action, confidence, probabilities = action_answer(response)
        rows.append(
            {
                "case_id": scenario.case_id,
                "source": scenario.source,
                "state": scenario.name,
                "action": action,
                "confidence": confidence,
                "probabilities": probabilities,
                "server_latency_ms": float(response["latency_ms"]),
                "round_trip_latency_ms": round_trip_latency_ms,
            }
        )

    summary = summarize(rows)
    failures = evaluate_stage_a(summary)
    payload = {
        "methodology_note": (
            "Synthetic MIDI boundary reproduction benchmark. Natural corpus states do not "
            "constitute human turn-taking accuracy labels."
        ),
        "model": args.model,
        "seed": args.seed,
        "cases_per_state_per_source": args.cases_per_state_per_source,
        "states": sorted(states),
        "corpus_index_sha256_raw": hashlib.sha256(raw_index).hexdigest(),
        "corpus_index_sha256_canonical": canonical_json_sha256(corpus_index),
        "case_ids": [row["case_id"] for row in rows],
        "summary": summary,
        "gate": {
            "passed": not failures,
            "failures": failures,
        },
        "cases": rows,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
        newline="\n",
    )
    print(json.dumps({"summary": summary, "gate": payload["gate"]}, ensure_ascii=False, indent=2))
    if failures and not args.no_gate:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
