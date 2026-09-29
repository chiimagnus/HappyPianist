#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import Counter
import json
import math
import statistics
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Iterable

PYTHON_BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(PYTHON_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(PYTHON_BACKEND_ROOT))

from mido import Message, MetaMessage, MidiFile, MidiTrack, bpm2tempo, second2tick

from scripts.companion_semantic_benchmark import load_manifest, validate_manifest
from shared.aria_protocol import (
    ControlChangeEvent,
    GenerateParams,
    GenerateRequest,
    NoteEvent,
    ResultResponse,
    ordered_events,
)
from shared.companion_scenarios import (
    ParsedMIDI,
    Scenario,
    load_midi,
    notes_before,
    project_qwen_state,
    resolve_under_python_backend,
    sample_scenarios,
    scenario_path,
)
from shared.qwen_companion_protocol import (
    MODEL_ID,
    CompanionDecisionResponse,
    companion_state_payload,
)


GENERATING_ACTIONS = {"support", "sparse", "respond"}
E2E_CASES_PER_SOURCE_STATE = 5
ARIA_TECHNICAL_MAX_TOKENS = 64
ARIA_PROMPT_WINDOW_SECONDS = 3.0
HTTP_TIMEOUT_SECONDS = 45.0


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
    parser.add_argument(
        "--stage-a-results",
        type=Path,
        default=Path(".outputs/companion-semantic-benchmark/results.json"),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(".outputs/companion-service-e2e"),
    )
    parser.add_argument("--qwen-host", default="127.0.0.1")
    parser.add_argument("--qwen-port", type=int, default=8767)
    parser.add_argument("--aria-host", default="127.0.0.1")
    parser.add_argument("--aria-port", type=int, default=8766)
    return parser.parse_args()


def select_service_scenarios(scenarios: list[Scenario]) -> list[Scenario]:
    selected: list[Scenario] = []
    counts: Counter[tuple[str, str]] = Counter()
    expected_buckets = {(scenario.source, scenario.name) for scenario in scenarios}
    for scenario in scenarios:
        key = (scenario.source, scenario.name)
        if counts[key] >= E2E_CASES_PER_SOURCE_STATE:
            continue
        selected.append(scenario)
        counts[key] += 1

    missing = sorted(
        key
        for key in expected_buckets
        if counts[key] != E2E_CASES_PER_SOURCE_STATE
    )
    if missing:
        raise RuntimeError(f"Stage A does not contain five service cases for buckets: {missing}")
    return selected


def load_fixed_scenarios(
    corpus_index: dict[str, Any],
) -> tuple[dict[str, Any], list[Scenario]]:
    manifest = load_manifest()
    full_stage_a = sample_scenarios(
        corpus_index,
        states=set(manifest["states"]),
        cases_per_state_per_source=int(manifest["cases_per_state_per_source"]),
        seed=int(manifest["seed"]),
    )
    validate_manifest(corpus_index, full_stage_a, manifest)
    return manifest, select_service_scenarios(full_stage_a)


def load_stage_a_actions(
    path: Path,
    *,
    manifest: dict[str, Any],
) -> dict[str, str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    expected = {
        "model": MODEL_ID,
        "manifest_version": manifest["version"],
        "projection_version": manifest["projection_version"],
        "corpus_index_sha256_canonical": manifest["corpus_index_sha256_canonical"],
        "case_ids_sha256": manifest["case_ids_sha256"],
    }
    for key, value in expected.items():
        if payload.get(key) != value:
            raise RuntimeError(f"Stage A result identity mismatch for {key}")
    if payload.get("case_ids") != manifest["case_ids"]:
        raise RuntimeError("Stage A result case IDs do not match the fixed manifest")

    actions: dict[str, str] = {}
    for row in payload.get("cases", []):
        case_id = str(row["case_id"])
        if case_id in actions:
            raise RuntimeError(f"duplicate Stage A case ID: {case_id}")
        actions[case_id] = str(row["action"])
    if set(actions) != set(manifest["case_ids"]):
        raise RuntimeError("Stage A result actions do not cover the fixed manifest")
    return actions


def aria_request(parsed: ParsedMIDI, scenario: Scenario) -> GenerateRequest:
    context = notes_before(parsed, scenario.cutoff, ARIA_PROMPT_WINDOW_SECONDS)
    if not context:
        raise RuntimeError("no prompt notes available")
    window_start = max(0.0, scenario.cutoff - ARIA_PROMPT_WINDOW_SECONDS)

    events: list[Any] = [
        NoteEvent(
            note=note.note,
            velocity=note.velocity,
            time=max(0.0, note.start - window_start),
            duration=note.duration,
        )
        for note in context
    ]
    for cc in parsed.ccs:
        if cc.controller == 64 and window_start <= cc.time <= scenario.cutoff:
            events.append(
                ControlChangeEvent(
                    controller=64,
                    value=cc.value,
                    time=max(0.0, cc.time - window_start),
                )
            )
    return GenerateRequest(
        events=ordered_events(events),
        params=GenerateParams(max_tokens=ARIA_TECHNICAL_MAX_TOKENS),
    )


def post_json(url: str, payload: dict[str, Any]) -> tuple[dict[str, Any], float]:
    data = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url=url,
        method="POST",
        headers={"Content-Type": "application/json"},
        data=data,
    )
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {error.code} from {url}: {body}") from error
    return body, (time.perf_counter() - started) * 1000.0


def output_note_signature(events: Iterable[Any], limit: int = 8) -> list[tuple[int, int]]:
    result: list[tuple[int, int]] = []
    for event in events:
        if isinstance(event, NoteEvent):
            result.append((event.note, event.velocity))
            if len(result) >= limit:
                break
    return result


def prompt_note_signature(request: GenerateRequest, limit: int = 8) -> list[tuple[int, int]]:
    notes = [
        (event.note, event.velocity)
        for event in request.events
        if isinstance(event, NoteEvent)
    ]
    return notes[-limit:]


def validate_generated_events(
    request: GenerateRequest,
    events: list[Any],
) -> dict[str, Any]:
    notes = [event for event in events if isinstance(event, NoteEvent)]
    if not notes:
        raise AssertionError("Aria output has no note events")
    for note in notes:
        values = (float(note.time), float(note.duration))
        if not all(math.isfinite(value) for value in values):
            raise AssertionError(f"non-finite note timing: {note}")
        if not 0 <= note.note <= 127:
            raise AssertionError(f"invalid note: {note.note}")
        if not 0 <= note.velocity <= 127:
            raise AssertionError(f"invalid velocity: {note.velocity}")
        if note.time < 0 or note.duration <= 0:
            raise AssertionError(f"invalid note timing: {note}")
    for event in events:
        if isinstance(event, ControlChangeEvent):
            if not math.isfinite(float(event.time)) or event.time < 0:
                raise AssertionError(f"invalid control timing: {event}")

    output_signature = output_note_signature(events)
    prompt_signature = prompt_note_signature(request)
    compared = min(len(output_signature), len(prompt_signature))
    if (
        compared >= 4
        and output_signature[:compared] == prompt_signature[-compared:]
    ):
        raise AssertionError("generated output appears to echo the prompt")

    return {
        "note_count": len(notes),
        "event_count": len(events),
        "first_note_time": min(float(note.time) for note in notes),
        "last_note_end": max(float(note.time + note.duration) for note in notes),
    }


def write_midi(events: list[Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tempo = bpm2tempo(120)
    ticks_per_beat = 480
    midi = MidiFile(ticks_per_beat=ticks_per_beat)
    track = MidiTrack()
    midi.tracks.append(track)
    track.append(MetaMessage("set_tempo", tempo=tempo, time=0))

    timeline: list[tuple[float, int, Message]] = []
    order = 0
    for event in events:
        if isinstance(event, NoteEvent):
            timeline.append(
                (
                    float(event.time),
                    order,
                    Message(
                        "note_on",
                        note=event.note,
                        velocity=event.velocity,
                        channel=0,
                        time=0,
                    ),
                )
            )
            order += 1
            timeline.append(
                (
                    float(event.time + event.duration),
                    order,
                    Message(
                        "note_off",
                        note=event.note,
                        velocity=0,
                        channel=0,
                        time=0,
                    ),
                )
            )
            order += 1
        elif isinstance(event, ControlChangeEvent):
            timeline.append(
                (
                    float(event.time),
                    order,
                    Message(
                        "control_change",
                        control=event.controller,
                        value=event.value,
                        channel=0,
                        time=0,
                    ),
                )
            )
            order += 1

    timeline.sort(key=lambda item: (item[0], item[1]))
    previous_time = 0.0
    for absolute_time, _, message in timeline:
        delta = max(0.0, absolute_time - previous_time)
        message.time = int(round(second2tick(delta, ticks_per_beat, tempo)))
        track.append(message)
        previous_time = absolute_time
    midi.save(path)


def validate_written_midi(path: Path) -> dict[str, int]:
    midi = MidiFile(path)
    active: Counter[tuple[int, int]] = Counter()
    note_ons = 0
    note_offs = 0
    for track in midi.tracks:
        for message in track:
            if message.type == "note_on" and message.velocity > 0:
                active[(message.channel, message.note)] += 1
                note_ons += 1
            elif message.type == "note_off" or (
                message.type == "note_on" and message.velocity == 0
            ):
                key = (message.channel, message.note)
                if active[key] <= 0:
                    raise AssertionError(f"unmatched note-off in {path}: {key}")
                active[key] -= 1
                note_offs += 1
    dangling = {key: count for key, count in active.items() if count}
    if dangling:
        raise AssertionError(f"unmatched note-on in {path}: {dangling}")
    if note_ons == 0 or note_ons != note_offs:
        raise AssertionError(f"invalid note balance in {path}: on={note_ons} off={note_offs}")
    return {"midi_note_on_count": note_ons, "midi_note_off_count": note_offs}


def action_counts(rows: list[dict[str, Any]]) -> dict[str, int]:
    return dict(sorted(Counter(str(row["action"]) for row in rows if row.get("action")).items()))


def percentile(values: list[float], quantile: float) -> float:
    ordered = sorted(values)
    if not ordered:
        raise ValueError("percentile requires values")
    if len(ordered) == 1:
        return ordered[0]
    index = (len(ordered) - 1) * quantile
    lower = int(index)
    upper = min(lower + 1, len(ordered) - 1)
    fraction = index - lower
    return ordered[lower] * (1.0 - fraction) + ordered[upper] * fraction


def latency_summary(values: list[float]) -> dict[str, float] | None:
    if not values:
        return None
    return {
        "median": statistics.median(values),
        "p95": percentile(values, 0.95),
        "max": max(values),
    }


def technical_gate(
    rows: list[dict[str, Any]],
    *,
    reference_actions: dict[str, str],
) -> dict[str, Any]:
    reasons: list[str] = []
    decision_errors = [row for row in rows if row.get("decision_error")]
    if decision_errors:
        reasons.append(f"decision_errors:{len(decision_errors)}")

    missing_references = [
        row["case_id"] for row in rows if row["case_id"] not in reference_actions
    ]
    if missing_references:
        reasons.append(f"missing_stage_a_references:{len(missing_references)}")

    mismatches = [
        row["case_id"]
        for row in rows
        if row.get("action")
        and reference_actions.get(row["case_id"]) != row["action"]
    ]
    if mismatches:
        reasons.append(f"stage_a_action_mismatches:{len(mismatches)}")

    generating_rows = [
        row for row in rows if row.get("action") in GENERATING_ACTIONS
    ]
    if not generating_rows:
        reasons.append("no_generating_actions")
    if any(row.get("generation_attempted") is not True for row in generating_rows):
        reasons.append("generating_action_without_aria_attempt")

    failed_generations = [
        row
        for row in generating_rows
        if row.get("generation_attempted") and row.get("generated") is not True
    ]
    if failed_generations:
        reasons.append(f"generation_failures:{len(failed_generations)}")

    if not any(row.get("generated") is True for row in rows):
        reasons.append("no_successful_aria_generation")

    return {
        "passed": not reasons,
        "reasons": reasons,
        "action_mismatch_case_ids": mismatches,
        "generation_failure_case_ids": [row["case_id"] for row in failed_generations],
    }


def main() -> int:
    args = parse_args()
    corpus_index_path = resolve_under_python_backend(args.corpus_index)
    maestro_root = resolve_under_python_backend(args.maestro_root)
    pop909_root = resolve_under_python_backend(args.pop909_root)
    stage_a_results_path = resolve_under_python_backend(args.stage_a_results)
    output_dir = resolve_under_python_backend(args.output_dir)
    midi_output_dir = output_dir / "midi"
    output_dir.mkdir(parents=True, exist_ok=True)

    corpus_index = json.loads(corpus_index_path.read_text(encoding="utf-8"))
    manifest, scenarios = load_fixed_scenarios(corpus_index)
    reference_actions = load_stage_a_actions(
        stage_a_results_path,
        manifest=manifest,
    )
    qwen_url = f"http://{args.qwen_host}:{args.qwen_port}/v1/companion-decision"
    aria_url = f"http://{args.aria_host}:{args.aria_port}/generate"

    rows: list[dict[str, Any]] = []
    midi_cache: dict[Path, ParsedMIDI] = {}

    for case_index, scenario in enumerate(scenarios):
        row: dict[str, Any] = {
            "case_id": scenario.case_id,
            "source": scenario.source,
            "state": scenario.name,
            "action": None,
            "generation_attempted": False,
            "generated": False,
        }
        try:
            midi_path = scenario_path(
                scenario,
                maestro_root=maestro_root,
                pop909_root=pop909_root,
            )
            parsed = midi_cache.get(midi_path)
            if parsed is None:
                parsed = load_midi(midi_path)
                midi_cache[midi_path] = parsed

            decision_state = project_qwen_state(
                parsed,
                scenario.cutoff,
                is_ai_playback_active=scenario.ai_playback_active,
                user_note_on_since_ai_playback_started=(
                    scenario.ai_playback_active and scenario.name == "takeover_overlay"
                ),
            )
            decision_payload, qwen_rtt_ms = post_json(
                qwen_url,
                {"state": companion_state_payload(decision_state)},
            )
            decision = CompanionDecisionResponse.model_validate(decision_payload)
            row.update(
                {
                    "action": decision.action,
                    "semantic_scores": decision.semantic_scores.model_dump(),
                    "semantic_order_gaps": decision.semantic_order_gaps.model_dump(),
                    "qwen_http_rtt_ms": qwen_rtt_ms,
                    "qwen_server_latency_ms": float(decision.server_latency_ms),
                    "stage_a_action": reference_actions.get(scenario.case_id),
                }
            )

            if decision.action in GENERATING_ACTIONS:
                row["generation_attempted"] = True
                request = aria_request(parsed, scenario)
                response_payload, aria_rtt_ms = post_json(
                    aria_url,
                    request.model_dump(),
                )
                response = ResultResponse.model_validate(response_payload)
                events = ordered_events(response.events)
                validation = validate_generated_events(request, events)
                safe_stem = Path(scenario.file).stem
                output_path = (
                    midi_output_dir
                    / f"{case_index:04d}-{scenario.source}-{safe_stem}-{scenario.name}-{decision.action}.mid"
                )
                write_midi(events, output_path)
                midi_validation = validate_written_midi(output_path)
                row.update(
                    {
                        "generated": True,
                        "output": str(output_path),
                        "aria_http_rtt_ms": aria_rtt_ms,
                        "aria_server_latency_ms": float(response.latency_ms),
                        **validation,
                        **midi_validation,
                    }
                )
        except Exception as error:
            if row["action"] is None:
                row["decision_error"] = f"{type(error).__name__}: {error}"
            else:
                row["generation_error"] = f"{type(error).__name__}: {error}"

        rows.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)

    gate = technical_gate(rows, reference_actions=reference_actions)
    by_state = {
        state: action_counts([row for row in rows if row["state"] == state])
        for state in sorted({str(row["state"]) for row in rows})
    }
    by_source_state = {
        source: {
            state: action_counts(
                [
                    row
                    for row in rows
                    if row["source"] == source and row["state"] == state
                ]
            )
            for state in sorted(
                {str(row["state"]) for row in rows if row["source"] == source}
            )
        }
        for source in sorted({str(row["source"]) for row in rows})
    }

    qwen_rtts = [float(row["qwen_http_rtt_ms"]) for row in rows if "qwen_http_rtt_ms" in row]
    qwen_server = [
        float(row["qwen_server_latency_ms"])
        for row in rows
        if "qwen_server_latency_ms" in row
    ]
    aria_rtts = [float(row["aria_http_rtt_ms"]) for row in rows if "aria_http_rtt_ms" in row]
    aria_server = [
        float(row["aria_server_latency_ms"])
        for row in rows
        if "aria_server_latency_ms" in row
    ]

    summary = {
        "decision_cases": len(rows),
        "qwen_model": MODEL_ID,
        "manifest_version": manifest["version"],
        "case_ids": [row["case_id"] for row in rows],
        "actions": action_counts(rows),
        "actions_by_state": by_state,
        "actions_by_source_state": by_source_state,
        "qwen_http_rtt_ms": latency_summary(qwen_rtts),
        "qwen_server_latency_ms": latency_summary(qwen_server),
        "aria_http_rtt_ms": latency_summary(aria_rtts),
        "aria_server_latency_ms": latency_summary(aria_server),
        "generation_attempts": sum(
            1 for row in rows if row["generation_attempted"]
        ),
        "generated_cases": sum(1 for row in rows if row["generated"]),
        "generation_failures": sum(
            1
            for row in rows
            if row["generation_attempted"] and row["generated"] is not True
        ),
        "technical_gate": gate,
    }
    payload = {
        "methodology_note": (
            "Service-level Qwen -> Aria E2E. It validates fixed Stage A case identity, "
            "real HTTP calls, schema, generated MIDI validity, prompt-echo rejection, "
            "and measured wall-clock service RTT. It does not duplicate Swift product "
            "policy and does not claim product realtime acceptance."
        ),
        "summary": summary,
        "cases": rows,
    }
    (output_dir / "results.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps({"summary": summary}, ensure_ascii=False, indent=2))
    return 0 if gate["passed"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
