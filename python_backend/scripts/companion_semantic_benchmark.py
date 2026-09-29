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
import urllib.error
import urllib.request

PYTHON_BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(PYTHON_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(PYTHON_BACKEND_ROOT))

from shared.companion_scenarios import (
    DENSITY_WINDOW_SECONDS,
    IOI_WINDOW_SECONDS,
    LOOKBACK_SECONDS,
    PROJECTION_VERSION,
    load_midi,
    project_qwen_state,
    resolve_under_python_backend,
    sample_scenarios,
    scenario_path,
)
from shared.companion_semantics import SEMANTIC_KEYS, SEMANTIC_THRESHOLD, action_mapping_metadata
from shared.qwen_companion_protocol import (
    ENGINE_ID,
    MODEL_ID,
    PROTOCOL_VERSION,
    companion_state_payload,
)


MANIFEST_PATH = PYTHON_BACKEND_ROOT / "tests/fixtures/companion_stage_a_manifest.json"
ACTION_COLLAPSE_SHARE = 0.90
REQUIRED_ACTIONS = {"listen", "support", "sparse", "yield", "respond"}
REQUEST_TIMEOUT_SECONDS = 2.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus-index", type=Path, default=Path(".outputs/companion-corpus/index.json"))
    parser.add_argument("--maestro-root", type=Path, default=Path(".datasets/maestro-v3/extracted/maestro-v3.0.0"))
    parser.add_argument("--pop909-root", type=Path, default=Path(".datasets/pop909/extracted/POP909"))
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8767)
    parser.add_argument("--output", type=Path, default=Path(".outputs/companion-semantic-benchmark/results.json"))
    return parser.parse_args()


def canonical_json_sha256(payload: Any) -> str:
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def case_ids_sha256(case_ids: list[str]) -> str:
    return hashlib.sha256("\n".join(case_ids).encode("utf-8")).hexdigest()


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
        semantic: statistics.median(float(row["semantic_scores"][semantic]) for row in rows)
        for semantic in SEMANTIC_KEYS
    }


def median_order_gaps(rows: list[dict[str, Any]]) -> dict[str, float]:
    if not rows:
        raise ValueError("order-gap median requires rows")
    return {
        semantic: statistics.median(float(row["semantic_order_gaps"][semantic]) for row in rows)
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
        source_rows = [row for row in rows if row["source"] == source]
        semantics_by_source_state[source] = {
            state: median_semantics([row for row in source_rows if row["state"] == state])
            for state in states
            if any(row["state"] == state for row in source_rows)
        }

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


PER_SOURCE_BOUNDARIES = {
    ("active_dense", "continuing"): True,
    ("active_dense", "finished"): False,
    ("active_dense", "space"): False,
    ("active_sparse", "continuing"): True,
    ("active_sparse", "finished"): False,
    ("active_sparse", "space"): True,
    ("settled_end", "continuing"): False,
    ("settled_end", "finished"): True,
    ("sustain_pause", "continuing"): True,
    ("sustain_pause", "finished"): False,
    ("takeover_overlay", "reasserted"): True,
}


def screening_diagnostics(summary: dict[str, Any]) -> dict[str, Any]:
    reasons: list[str] = []
    action_total = sum(int(value) for value in summary["actions"].values())
    dominant_action, dominant_count = max(summary["actions"].items(), key=lambda item: int(item[1]))
    dominant_share = int(dominant_count) / action_total
    if dominant_share >= ACTION_COLLAPSE_SHARE:
        reasons.append(f"action_collapse:{dominant_action}:{dominant_share:.3f}")

    missing_actions = sorted(REQUIRED_ACTIONS - set(summary["actions"]))
    if missing_actions:
        reasons.append("missing_actions:" + ",".join(missing_actions))

    by_source = summary["semantic_medians_by_source_state"]
    for source in summary["sources"]:
        for (state, semantic), should_be_true in PER_SOURCE_BOUNDARIES.items():
            value = float(by_source[source][state][semantic])
            observed_true = value >= SEMANTIC_THRESHOLD
            if observed_true != should_be_true:
                reasons.append(
                    f"semantic_boundary:{source}:{state}:{semantic}:{value:.3f}:expected_"
                    f"{'true' if should_be_true else 'false'}"
                )

    if action_rate(summary, "active_dense", "respond") >= 0.25:
        reasons.append("active_dense_respond_rate_too_high")
    if action_rate(summary, "settled_end", "respond") <= action_rate(summary, "active_dense", "respond"):
        reasons.append("settled_end_not_above_active_dense_on_respond")
    if action_rate(summary, "takeover_overlay", "yield") <= action_rate(summary, "active_dense", "yield"):
        reasons.append("takeover_overlay_not_above_active_dense_on_yield")
    return {
        "dominant_action": {"action": dominant_action, "share": dominant_share},
        "semantic_threshold": SEMANTIC_THRESHOLD,
        "automatic_stop_reasons": reasons,
        "passed": not reasons,
    }


def post_json(url: str, payload: dict[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        method="POST",
        headers={"Content-Type": "application/json"},
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
    )
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {error.code}: {body}") from error


def load_manifest() -> dict[str, Any]:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def validate_manifest(corpus_index: dict[str, Any], scenarios: list[Any], manifest: dict[str, Any]) -> None:
    if manifest["projection_version"] != PROJECTION_VERSION:
        raise RuntimeError("Stage A projection version does not match product projection")
    expected_projection_parameters = {
        "lookback_seconds": LOOKBACK_SECONDS,
        "ioi_window_seconds": IOI_WINDOW_SECONDS,
        "density_window_seconds": DENSITY_WINDOW_SECONDS,
    }
    if manifest.get("projection_parameters") != expected_projection_parameters:
        raise RuntimeError("Stage A projection parameters do not match product projection")
    if manifest.get("model") != MODEL_ID:
        raise RuntimeError("Stage A model identity does not match Qwen Companion service")
    if manifest.get("engine") != ENGINE_ID:
        raise RuntimeError("Stage A engine identity does not match Qwen Companion service")
    if str(manifest.get("protocol_version")) != PROTOCOL_VERSION:
        raise RuntimeError("Stage A protocol version does not match Qwen Companion service")
    if corpus_index.get("projection_version") != PROJECTION_VERSION:
        raise RuntimeError("corpus index projection version does not match product projection")
    if corpus_index.get("errors"):
        raise RuntimeError("corpus index contains parse errors")
    canonical_sha = canonical_json_sha256(corpus_index)
    if canonical_sha != manifest["corpus_index_sha256_canonical"]:
        raise RuntimeError("corpus index identity does not match Stage A manifest")
    case_ids = [scenario.case_id for scenario in scenarios]
    if case_ids != manifest["case_ids"]:
        raise RuntimeError("ordered Stage A case IDs do not match manifest")
    if case_ids_sha256(case_ids) != manifest["case_ids_sha256"]:
        raise RuntimeError("Stage A case ID digest does not match manifest")
    if float(manifest["semantic_threshold"]) != SEMANTIC_THRESHOLD:
        raise RuntimeError("Stage A semantic threshold does not match runtime contract")


def main() -> int:
    args = parse_args()
    manifest = load_manifest()
    index_path = resolve_under_python_backend(args.corpus_index)
    maestro_root = resolve_under_python_backend(args.maestro_root)
    pop909_root = resolve_under_python_backend(args.pop909_root)
    output = resolve_under_python_backend(args.output)
    corpus_index = json.loads(index_path.read_text(encoding="utf-8"))
    states = set(manifest["states"])
    scenarios = sample_scenarios(
        corpus_index,
        states=states,
        cases_per_state_per_source=int(manifest["cases_per_state_per_source"]),
        seed=int(manifest["seed"]),
    )
    validate_manifest(corpus_index, scenarios, manifest)

    url = f"http://{args.host}:{args.port}/v1/companion-decision"
    midi_cache: dict[Path, Any] = {}
    rows: list[dict[str, Any]] = []
    for scenario in scenarios:
        path = scenario_path(scenario, maestro_root=maestro_root, pop909_root=pop909_root)
        parsed = midi_cache.get(path)
        if parsed is None:
            parsed = load_midi(path)
            midi_cache[path] = parsed
        state = project_qwen_state(
            parsed,
            scenario.cutoff,
            is_ai_playback_active=scenario.ai_playback_active,
            user_note_on_since_ai_playback_started=(scenario.name == "takeover_overlay"),
        )
        started = time.perf_counter()
        response = post_json(url, {"state": companion_state_payload(state)})
        round_trip_latency_ms = (time.perf_counter() - started) * 1000
        if response.get("model") != MODEL_ID:
            raise RuntimeError("Qwen companion service returned an unexpected model identity")
        if response.get("usage", {}).get("output_tokens") != 0:
            raise RuntimeError("Qwen companion service returned non-zero output_tokens")
        rows.append(
            {
                "case_id": scenario.case_id,
                "source": scenario.source,
                "state": scenario.name,
                "semantic_scores": response["semantic_scores"],
                "semantic_order_gaps": response["semantic_order_gaps"],
                "action": str(response["action"]),
                "server_latency_ms": float(response["server_latency_ms"]),
                "round_trip_latency_ms": round_trip_latency_ms,
            }
        )

    summary = summarize(rows)
    screening = screening_diagnostics(summary)
    payload = {
        "methodology_note": "Fixed Qwen Companion Stage A; service owns semantic questions/A-B aggregation/action mapping and each corpus source is checked against the same observable boundaries.",
        "model": MODEL_ID,
        "manifest_version": manifest["version"],
        "projection_version": manifest["projection_version"],
        "seed": manifest["seed"],
        "cases_per_state_per_source": manifest["cases_per_state_per_source"],
        "states": manifest["states"],
        "corpus_index_sha256_canonical": manifest["corpus_index_sha256_canonical"],
        "case_ids_sha256": manifest["case_ids_sha256"],
        "case_ids": [row["case_id"] for row in rows],
        "action_mapping": action_mapping_metadata(),
        "summary": summary,
        "screening": screening,
        "cases": rows,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
    print(json.dumps({"summary": summary, "screening": screening}, ensure_ascii=False, indent=2))
    return 0 if screening["passed"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
