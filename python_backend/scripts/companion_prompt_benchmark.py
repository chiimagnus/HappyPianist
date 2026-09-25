#!/usr/bin/env python3
from __future__ import annotations

import argparse
import itertools
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

PYTHON_BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(PYTHON_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(PYTHON_BACKEND_ROOT))

from shared.companion_prompt_profiles import ACTION_THRESHOLD, SEMANTIC_KEYS, profile_names


STAGE_A_CASES_PER_STATE_PER_SOURCE = 10
ACTION_COLLAPSE_SHARE = 0.90
SEMANTIC_EXTREME_SHARE = 0.90
DENSE_RESPOND_SHARE = 0.25
CROSS_SOURCE_DIRECTION_GAP = 0.15


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--qwen-host", default="127.0.0.1")
    parser.add_argument("--qwen-port", type=int, default=8767)
    parser.add_argument("--qwen-model", required=True)
    parser.add_argument(
        "--cases-per-state-per-source",
        type=int,
        default=STAGE_A_CASES_PER_STATE_PER_SOURCE,
    )
    parser.add_argument("--seed", type=int, default=20260920)
    parser.add_argument("--timeout", type=float, default=90.0)
    parser.add_argument(
        "--profiles",
        default=",".join(profile_names()),
        help="Comma-separated prompt profiles to evaluate.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(".outputs/companion-prompt-benchmark"),
    )
    return parser.parse_args()


def action_rate(summary: dict[str, Any], state: str, action: str) -> float:
    counts = summary["actions_by_state"][state]
    total = sum(int(count) for count in counts.values())
    return float(counts.get(action, 0)) / total if total else 0.0


def semantic_extreme_shares(cases: list[dict[str, Any]]) -> dict[str, float]:
    if not cases:
        raise ValueError("benchmark result contains no cases")
    return {
        key: sum(
            1
            for case in cases
            if float(case["semantic_scores"][key]) <= 0.15
            or float(case["semantic_scores"][key]) >= 0.85
        )
        / len(cases)
        for key in SEMANTIC_KEYS
    }


def cross_source_direction_conflicts(summary: dict[str, Any]) -> list[dict[str, Any]]:
    by_source = summary["semantic_medians_by_source_state"]
    conflicts: list[dict[str, Any]] = []
    for left, right in itertools.combinations(summary["sources"], 2):
        for state in summary["states"]:
            if state not in by_source[left] or state not in by_source[right]:
                continue
            for question in SEMANTIC_KEYS:
                left_value = float(by_source[left][state][question])
                right_value = float(by_source[right][state][question])
                crosses_midpoint = (left_value - 0.5) * (right_value - 0.5) < 0
                if crosses_midpoint and abs(left_value - right_value) >= CROSS_SOURCE_DIRECTION_GAP:
                    conflicts.append(
                        {
                            "sources": [left, right],
                            "state": state,
                            "question": question,
                            "values": {
                                left: left_value,
                                right: right_value,
                            },
                        }
                    )
    return conflicts


def screening_diagnostics(result: dict[str, Any]) -> dict[str, Any]:
    summary = result["summary"]
    cases = result["cases"]
    actions = {str(key): int(value) for key, value in summary["actions"].items()}
    total_actions = sum(actions.values())
    dominant_action, dominant_count = max(actions.items(), key=lambda item: item[1])
    dominant_share = dominant_count / total_actions

    extremes = semantic_extreme_shares(cases)
    dense_finished = float(summary["semantic_medians_by_state"]["active_dense"]["finished"])
    dense_respond_rate = action_rate(summary, "active_dense", "respond")
    dense_reasserted = float(
        summary["semantic_medians_by_state"]["active_dense"]["reasserted"]
    )
    dense_yield_rate = action_rate(summary, "active_dense", "yield")
    takeover_reasserted = float(
        summary["semantic_medians_by_state"]["takeover_overlay"]["reasserted"]
    )
    takeover_yield_rate = action_rate(summary, "takeover_overlay", "yield")
    sustain_continuing = float(
        summary["semantic_medians_by_state"]["sustain_pause"]["continuing"]
    )
    sustain_finished = float(
        summary["semantic_medians_by_state"]["sustain_pause"]["finished"]
    )

    automatic_stop_reasons: list[str] = []
    if dominant_share >= ACTION_COLLAPSE_SHARE:
        automatic_stop_reasons.append(
            f"action_collapse:{dominant_action}:{dominant_share:.3f}"
        )
    for question, share in extremes.items():
        if share >= SEMANTIC_EXTREME_SHARE:
            automatic_stop_reasons.append(
                f"semantic_extreme_collapse:{question}:{share:.3f}"
            )
    if takeover_reasserted <= dense_reasserted:
        automatic_stop_reasons.append(
            "takeover_reasserted_not_above_active_dense"
        )
    if takeover_yield_rate <= dense_yield_rate:
        automatic_stop_reasons.append("takeover_yield_not_above_active_dense")
    if dense_finished >= ACTION_THRESHOLD or dense_respond_rate >= DENSE_RESPOND_SHARE:
        automatic_stop_reasons.append(
            f"active_dense_overfinished_or_responding:{dense_finished:.3f}:{dense_respond_rate:.3f}"
        )

    source_conflicts = cross_source_direction_conflicts(summary)
    return {
        "dominant_action": {
            "action": dominant_action,
            "share": dominant_share,
        },
        "semantic_extreme_shares": extremes,
        "key_boundaries": {
            "active_dense": {
                "finished_median": dense_finished,
                "respond_rate": dense_respond_rate,
            },
            "sustain_pause": {
                "continuing_median": sustain_continuing,
                "finished_median": sustain_finished,
            },
            "takeover_overlay": {
                "reasserted_median": takeover_reasserted,
                "yield_rate": takeover_yield_rate,
                "active_dense_reasserted_median": dense_reasserted,
            },
        },
        "cross_source_direction_conflicts": source_conflicts,
        "automatic_stop_reasons": automatic_stop_reasons,
        "requires_manual_cross_source_review": bool(source_conflicts),
    }


def main() -> int:
    args = parse_args()
    output_dir = (
        args.output_dir
        if args.output_dir.is_absolute()
        else PYTHON_BACKEND_ROOT / args.output_dir
    ).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    script = Path(__file__).with_name("companion_e2e_acceptance.py")
    selected_profiles = [
        profile.strip()
        for profile in args.profiles.split(",")
        if profile.strip()
    ]
    unknown_profiles = sorted(set(selected_profiles) - set(profile_names()))
    if unknown_profiles:
        raise ValueError(f"unknown prompt profiles: {unknown_profiles}")
    if not selected_profiles:
        raise ValueError("at least one prompt profile is required")

    combined: dict[str, Any] = {
        "seed": args.seed,
        "cases_per_state_per_source": args.cases_per_state_per_source,
        "profiles": {},
    }
    reference_case_ids: list[str] | None = None
    reference_corpus_sha256: str | None = None

    for profile in selected_profiles:
        profile_dir = output_dir / profile
        command = [
            sys.executable,
            str(script),
            "--decision-only",
            "--qwen-host",
            args.qwen_host,
            "--qwen-port",
            str(args.qwen_port),
            "--qwen-model",
            args.qwen_model,
            "--prompt-profile",
            profile,
            "--cases-per-state-per-source",
            str(args.cases_per_state_per_source),
            "--seed",
            str(args.seed),
            "--timeout",
            str(args.timeout),
            "--output-dir",
            str(profile_dir),
        ]
        print(f"[prompt-benchmark] running {profile}", flush=True)
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL)

        result_path = profile_dir / "results.json"
        result = json.loads(result_path.read_text(encoding="utf-8"))
        summary = result["summary"]
        case_ids = [str(case_id) for case_id in summary["case_ids"]]
        corpus_sha256 = str(summary["corpus_index_sha256"])

        if reference_case_ids is None:
            reference_case_ids = case_ids
            reference_corpus_sha256 = corpus_sha256
        else:
            if case_ids != reference_case_ids:
                raise AssertionError(
                    f"profile {profile!r} did not use the same ordered case IDs"
                )
            if corpus_sha256 != reference_corpus_sha256:
                raise AssertionError(
                    f"profile {profile!r} did not use the same corpus index"
                )

        diagnostics = screening_diagnostics(result)
        combined["profiles"][profile] = {
            "summary": summary,
            "screening": diagnostics,
        }
        print(
            json.dumps(
                {
                    "profile": profile,
                    "actions": summary["actions"],
                    "latency": summary["decision_latency_ms"],
                    "key_boundaries": diagnostics["key_boundaries"],
                    "automatic_stop_reasons": diagnostics["automatic_stop_reasons"],
                    "cross_source_conflicts": len(
                        diagnostics["cross_source_direction_conflicts"]
                    ),
                },
                ensure_ascii=False,
            ),
            flush=True,
        )

    combined["case_ids"] = reference_case_ids or []
    combined["corpus_index_sha256"] = reference_corpus_sha256
    (output_dir / "summary.json").write_text(
        json.dumps(combined, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
