#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import random
import statistics
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

PYTHON_BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(PYTHON_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(PYTHON_BACKEND_ROOT))

from mido import Message, MetaMessage, MidiFile, MidiTrack, bpm2tempo, second2tick

from shared.companion_prompt_profiles import (
    action_from_semantics,
    action_mapping_metadata,
    classifier_payload,
    median_semantic_peak_probabilities,
    median_semantic_scores,
    profile_names,
    semantic_peak_probabilities,
    semantic_scores,
)
from shared.protocol_v2 import (
    ControlChangeEvent,
    GenerateParams,
    GenerateRequestV2,
    NoteEvent,
    ResultResponseV2,
    legalize_events,
)


GENERATING_ACTIONS = {"support", "sparse", "respond"}


@dataclass(frozen=True)
class ParsedNote:
    note: int
    velocity: int
    start: float
    duration: float


@dataclass(frozen=True)
class ParsedCC:
    controller: int
    value: int
    time: float


@dataclass(frozen=True)
class ParsedMIDI:
    notes: list[ParsedNote]
    ccs: list[ParsedCC]
    duration: float


@dataclass(frozen=True)
class Scenario:
    source: str
    file: str
    name: str
    cutoff: float
    provenance: str
    ai_playback_active: bool

    @property
    def case_id(self) -> str:
        return f"{self.source}|{self.name}|{self.file}|{self.cutoff:.6f}"


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
    parser.add_argument("--cases-per-state-per-source", type=int, default=5)
    parser.add_argument("--seed", type=int, default=20260920)
    parser.add_argument(
        "--states",
        default="active_dense,active_sparse,sustain_pause,natural_silence,settled_end,takeover_overlay",
    )
    parser.add_argument(
        "--decision-only",
        action="store_true",
        help="Evaluate Qwen decisions without calling Aria.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(".outputs/companion-decision-e2e"),
    )
    parser.add_argument("--qwen-host", default="127.0.0.1")
    parser.add_argument("--qwen-port", type=int, default=8767)
    parser.add_argument("--qwen-model", default="Qwen/Qwen3.5-0.8B")
    parser.add_argument(
        "--prompt-profile",
        choices=profile_names(),
        default="direct",
    )
    parser.add_argument("--aria-host", default="127.0.0.1")
    parser.add_argument("--aria-port", type=int, default=8766)
    parser.add_argument("--timeout", type=float, default=45.0)
    parser.add_argument("--prompt-window", type=float, default=3.0)
    parser.add_argument("--max-tokens", type=int, default=64)
    return parser.parse_args()


def load_midi(path: Path) -> ParsedMIDI:
    midi = MidiFile(path)
    current_time = 0.0
    active: dict[tuple[int, int], list[tuple[float, int]]] = {}
    notes: list[ParsedNote] = []
    ccs: list[ParsedCC] = []

    for message in midi:
        current_time += float(message.time)
        channel = int(getattr(message, "channel", 0))
        if message.type == "note_on" and message.velocity > 0:
            active.setdefault((channel, int(message.note)), []).append(
                (current_time, int(message.velocity))
            )
        elif message.type in {"note_off", "note_on"}:
            key = (channel, int(message.note))
            stack = active.get(key)
            if stack:
                started_at, velocity = stack.pop(0)
                notes.append(
                    ParsedNote(
                        note=int(message.note),
                        velocity=velocity,
                        start=started_at,
                        duration=max(0.01, current_time - started_at),
                    )
                )
                if not stack:
                    active.pop(key, None)
        elif message.type == "control_change" and int(message.control) in {7, 11, 64}:
            ccs.append(
                ParsedCC(
                    controller=int(message.control),
                    value=int(message.value),
                    time=current_time,
                )
            )

    for (_, note), stack in active.items():
        for started_at, velocity in stack:
            notes.append(
                ParsedNote(
                    note=note,
                    velocity=velocity,
                    start=started_at,
                    duration=max(0.01, current_time - started_at),
                )
            )

    notes.sort(key=lambda n: (n.start, n.note))
    ccs.sort(key=lambda e: e.time)
    return ParsedMIDI(notes=notes, ccs=ccs, duration=current_time)


def resolve_under_python_backend(path: Path) -> Path:
    if path.is_absolute():
        return path
    return Path(__file__).resolve().parents[1] / path


def sample_scenarios(
    corpus_index: dict[str, Any],
    *,
    states: set[str],
    cases_per_state_per_source: int,
    seed: int,
) -> list[Scenario]:
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for candidate in corpus_index.get("candidates", []):
        state = str(candidate["state"])
        if state not in states:
            continue
        source = str(candidate["source"])
        grouped.setdefault((source, state), []).append(candidate)

    if cases_per_state_per_source <= 0:
        raise ValueError("cases_per_state_per_source must be positive")

    sources = sorted(
        str(source)
        for source, count in corpus_index.get("files", {}).items()
        if int(count) > 0
    )
    if not sources:
        sources = sorted({source for source, _ in grouped})

    rng = random.Random(seed)
    sampled: list[Scenario] = []
    for source in sources:
        for state in sorted(states):
            candidates = grouped.get((source, state), [])
            if len(candidates) < cases_per_state_per_source:
                raise RuntimeError(
                    f"insufficient candidates for {source}/{state}: "
                    f"need {cases_per_state_per_source}, have {len(candidates)}"
                )
            for candidate in rng.sample(candidates, cases_per_state_per_source):
                sampled.append(
                    Scenario(
                        source=source,
                        file=str(candidate["file"]),
                        name=state,
                        cutoff=float(candidate["timestamp"]),
                        provenance=str(candidate["provenance"]),
                        ai_playback_active=state == "takeover_overlay",
                    )
                )
    return sampled


def scenario_path(
    scenario: Scenario,
    *,
    maestro_root: Path,
    pop909_root: Path,
) -> Path:
    if scenario.source == "maestro":
        return maestro_root / scenario.file
    if scenario.source == "pop909":
        return pop909_root / scenario.file
    raise ValueError(f"unsupported corpus source: {scenario.source}")


def notes_before(parsed: ParsedMIDI, cutoff: float, window: float) -> list[ParsedNote]:
    start = cutoff - window
    return [
        note
        for note in parsed.notes
        if note.start <= cutoff and (note.start + note.duration) >= start
    ]


def latest_sustain_value(parsed: ParsedMIDI, cutoff: float) -> int:
    value = 0
    for event in parsed.ccs:
        if event.time > cutoff:
            break
        if event.controller == 64:
            value = event.value
    return value


def velocity_trend(notes: list[ParsedNote]) -> float:
    if len(notes) < 2:
        return 0.0
    velocities = [n.velocity for n in notes]
    midpoint = len(velocities) // 2
    first = velocities[:midpoint]
    second = velocities[midpoint:]
    if not first or not second:
        return 0.0
    return statistics.mean(second) - statistics.mean(first)


def median_ioi(notes: list[ParsedNote]) -> float | None:
    onsets = sorted({n.start for n in notes})
    if len(onsets) < 2:
        return None
    return statistics.median(b - a for a, b in zip(onsets, onsets[1:]))


def decision_payload(
    parsed: ParsedMIDI,
    scenario: Scenario,
    prompt_window: float,
) -> dict[str, Any]:
    context = notes_before(parsed, scenario.cutoff, prompt_window)
    now = scenario.cutoff
    recent_for_density = [n for n in context if n.start >= scenario.cutoff - 1.0]
    active_notes = [
        n for n in context if n.start <= now < (n.start + n.duration)
    ]
    last_note_on = max((n.start for n in context), default=None)
    last_event = max(
        [
            *(n.start for n in context if n.start <= now),
            *(n.start + n.duration for n in context if n.start + n.duration <= now),
            *(cc.time for cc in parsed.ccs if cc.time <= now),
        ],
        default=None,
    )
    pitch_center = statistics.mean(n.note for n in context) if context else None
    tail = context[-16:]

    return {
        "held_notes_count": len(active_notes),
        "sustain_value": latest_sustain_value(parsed, scenario.cutoff),
        "recent_ioi_median_seconds": median_ioi(context),
        "recent_velocity_trend": velocity_trend(context),
        "recent_note_density_per_second": float(len(recent_for_density)),
        "seconds_since_last_user_event": (
            None if last_event is None else max(0.0, now - last_event)
        ),
        "seconds_since_last_note_on": (
            None if last_note_on is None else max(0.0, now - last_note_on)
        ),
        "active_pitch_center": pitch_center,
        "is_ai_playback_active": scenario.ai_playback_active,
        "recent_notes": [
            {
                "midi": note.note,
                "velocity": note.velocity,
                "onset_seconds_ago": max(0.0, now - note.start),
                "duration_seconds": note.duration,
            }
            for note in tail
        ],
    }


def generation_horizon_seconds(action: str, held_notes_count: int) -> float:
    if action == "sparse":
        return 0.45
    if action == "support":
        return 0.70 if held_notes_count > 0 else 0.60
    if action == "respond":
        return 0.70
    return 0.0


def aria_request(
    parsed: ParsedMIDI,
    scenario: Scenario,
    prompt_window: float,
    max_tokens: int,
) -> GenerateRequestV2:
    context = notes_before(parsed, scenario.cutoff, prompt_window)
    if not context:
        raise RuntimeError("no prompt notes available")
    window_start = max(0.0, scenario.cutoff - prompt_window)

    events: list[Any] = [
        NoteEvent(
            note=note.note,
            velocity=note.velocity,
            time=max(0.0, note.start - window_start),
            duration=max(0.01, note.duration),
        )
        for note in context
    ]
    for cc in parsed.ccs:
        if window_start <= cc.time <= scenario.cutoff:
            events.append(
                ControlChangeEvent(
                    controller=cc.controller,
                    value=cc.value,
                    time=max(0.0, cc.time - window_start),
                )
            )
    return GenerateRequestV2(
        events=legalize_events(events),
        params=GenerateParams(max_tokens=max_tokens),
    )


def post_json(url: str, payload: dict[str, Any], timeout: float) -> dict[str, Any]:
    data = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url=url,
        method="POST",
        headers={"Content-Type": "application/json"},
        data=data,
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {error.code} from {url}: {body}") from error


def output_note_signature(events: Iterable[Any], limit: int = 8) -> list[tuple[int, int]]:
    result: list[tuple[int, int]] = []
    for event in events:
        if isinstance(event, NoteEvent):
            result.append((event.note, event.velocity))
            if len(result) >= limit:
                break
    return result


def prompt_note_signature(request: GenerateRequestV2, limit: int = 8) -> list[tuple[int, int]]:
    result: list[tuple[int, int]] = []
    for event in request.events:
        if isinstance(event, NoteEvent):
            result.append((event.note, event.velocity))
    return result[-limit:]


def validate_generated_events(
    request: GenerateRequestV2,
    events: list[Any],
) -> dict[str, Any]:
    notes = [event for event in events if isinstance(event, NoteEvent)]
    if not notes:
        raise AssertionError("Aria output has no note events")
    for note in notes:
        if not 0 <= note.note <= 127:
            raise AssertionError(f"invalid note: {note.note}")
        if not 0 <= note.velocity <= 127:
            raise AssertionError(f"invalid velocity: {note.velocity}")
        if note.time < 0 or note.duration <= 0:
            raise AssertionError(f"invalid note timing: {note}")
    output_signature = output_note_signature(events)
    prompt_signature = prompt_note_signature(request)
    exact_echo = (
        len(output_signature) >= 4
        and output_signature == prompt_signature[: len(output_signature)]
    )
    if exact_echo:
        raise AssertionError("generated output appears to echo the prompt")
    return {
        "note_count": len(notes),
        "event_count": len(events),
        "first_note_time": min(note.time for note in notes),
        "last_note_end": max(note.time + note.duration for note in notes),
        "prompt_signature": prompt_signature,
        "output_signature": output_signature,
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


def action_counts(rows: list[dict[str, Any]]) -> dict[str, int]:
    actions = sorted({str(row["action"]) for row in rows})
    return {
        action: sum(1 for row in rows if row["action"] == action)
        for action in actions
    }


def main() -> int:
    args = parse_args()
    corpus_index_path = resolve_under_python_backend(args.corpus_index)
    maestro_root = resolve_under_python_backend(args.maestro_root)
    pop909_root = resolve_under_python_backend(args.pop909_root)
    output_dir = resolve_under_python_backend(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    corpus_index_bytes = corpus_index_path.read_bytes()
    corpus_index_sha256 = hashlib.sha256(corpus_index_bytes).hexdigest()
    corpus_index = json.loads(corpus_index_bytes)
    selected_states = {
        state.strip()
        for state in args.states.split(",")
        if state.strip()
    }
    scenarios = sample_scenarios(
        corpus_index,
        states=selected_states,
        cases_per_state_per_source=args.cases_per_state_per_source,
        seed=args.seed,
    )
    if not scenarios:
        raise RuntimeError("corpus index produced no scenarios for the selected states")

    qwen_url = f"http://{args.qwen_host}:{args.qwen_port}/v1/classifier"
    aria_url = f"http://{args.aria_host}:{args.aria_port}/generate"

    results: list[dict[str, Any]] = []
    generated_count = 0
    midi_cache: dict[Path, ParsedMIDI] = {}

    for case_index, scenario in enumerate(scenarios):
        midi_path = scenario_path(
            scenario,
            maestro_root=maestro_root,
            pop909_root=pop909_root,
        )
        parsed = midi_cache.get(midi_path)
        if parsed is None:
            parsed = load_midi(midi_path)
            midi_cache[midi_path] = parsed

        decision_state = decision_payload(parsed, scenario, args.prompt_window)
        decision_request = classifier_payload(
            model=args.qwen_model,
            state=decision_state,
            profile=args.prompt_profile,
        )
        decision = post_json(qwen_url, decision_request, args.timeout)
        if decision.get("usage", {}).get("output_tokens") != 0:
            raise AssertionError("Jev classifier returned non-zero output_tokens")
        scores = semantic_scores(decision)
        peak_probabilities = semantic_peak_probabilities(decision)
        action = action_from_semantics(decision_state, scores)
        row: dict[str, Any] = {
            "case_id": scenario.case_id,
            "source": scenario.source,
            "input": scenario.file,
            "state": scenario.name,
            "provenance": scenario.provenance,
            "timestamp": scenario.cutoff,
            "action": action,
            "prompt_profile": args.prompt_profile,
            "semantic_scores": scores,
            "semantic_peak_probabilities": peak_probabilities,
            "decision_latency_ms": int(decision["latency_ms"]),
            "generation_attempted": False,
            "generated": False,
        }

        if not args.decision_only and action in GENERATING_ACTIONS:
            row["generation_attempted"] = True
            try:
                request = aria_request(
                    parsed,
                    scenario,
                    args.prompt_window,
                    args.max_tokens,
                )
                response_payload = post_json(
                    aria_url,
                    request.model_dump(),
                    args.timeout,
                )
                response = ResultResponseV2.model_validate(response_payload)
                row["generation_latency_ms"] = response.latency_ms
                events = legalize_events(response.events)
                validation = validate_generated_events(request, events)
                held_notes_count = int(decision_state["held_notes_count"])
                horizon_seconds = generation_horizon_seconds(action, held_notes_count)
                realtime_note_count = sum(
                    1
                    for event in events
                    if isinstance(event, NoteEvent)
                    and float(event.time) <= horizon_seconds
                )
                safe_stem = Path(scenario.file).stem
                output_path = (
                    output_dir
                    / f"{case_index:04d}-{scenario.source}-{safe_stem}-{scenario.name}-{action}.mid"
                )
                write_midi(events, output_path)
                row.update(
                    {
                        "generated": True,
                        "output": str(output_path),
                        "realtime_horizon_seconds": horizon_seconds,
                        "realtime_note_count": realtime_note_count,
                        "realtime_window_pass": realtime_note_count > 0,
                        **validation,
                    }
                )
                generated_count += 1
            except Exception as error:
                row["generation_error"] = f"{type(error).__name__}: {error}"

        results.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)

    attempted_rows = [row for row in results if row["generation_attempted"]]
    generated_rows = [row for row in results if row["generated"]]
    failed_rows = [
        row for row in attempted_rows if row["generated"] is False
    ]
    realtime_pass_count = sum(
        1 for row in generated_rows if row.get("realtime_window_pass")
    )

    by_state: dict[str, dict[str, int]] = {}
    for state in sorted({str(row["state"]) for row in results}):
        by_state[state] = action_counts(
            [row for row in results if row["state"] == state]
        )

    by_source_state: dict[str, dict[str, dict[str, int]]] = {}
    for source in sorted({str(row["source"]) for row in results}):
        by_source_state[source] = {}
        source_rows = [row for row in results if row["source"] == source]
        for state in sorted({str(row["state"]) for row in source_rows}):
            by_source_state[source][state] = action_counts(
                [row for row in source_rows if row["state"] == state]
            )

    decision_latencies = [float(row["decision_latency_ms"]) for row in results]
    generation_latencies = [
        float(row["generation_latency_ms"])
        for row in attempted_rows
        if row.get("generation_latency_ms") is not None
    ]
    states_in_results = sorted({str(row["state"]) for row in results})
    sources_in_results = sorted({str(row["source"]) for row in results})
    semantic_by_state = {
        state: median_semantic_scores(
            [row for row in results if row["state"] == state]
        )
        for state in states_in_results
    }
    semantic_confidence_by_state = {
        state: median_semantic_peak_probabilities(
            [row for row in results if row["state"] == state]
        )
        for state in states_in_results
    }
    semantic_by_source_state: dict[str, dict[str, dict[str, float]]] = {}
    semantic_confidence_by_source_state: dict[str, dict[str, dict[str, float]]] = {}
    for source in sources_in_results:
        source_rows = [row for row in results if row["source"] == source]
        semantic_by_source_state[source] = {}
        semantic_confidence_by_source_state[source] = {}
        for state in states_in_results:
            state_rows = [row for row in source_rows if row["state"] == state]
            if not state_rows:
                continue
            semantic_by_source_state[source][state] = median_semantic_scores(state_rows)
            semantic_confidence_by_source_state[source][state] = (
                median_semantic_peak_probabilities(state_rows)
            )

    summary: dict[str, Any] = {
        "decision_cases": len(results),
        "decision_only": bool(args.decision_only),
        "qwen_model": args.qwen_model,
        "prompt_profile": args.prompt_profile,
        "action_mapping": action_mapping_metadata(),
        "corpus_index_sha256": corpus_index_sha256,
        "case_ids": [row["case_id"] for row in results],
        "sample_seed": args.seed,
        "cases_per_state_per_source": args.cases_per_state_per_source,
        "states": sorted(selected_states),
        "sources": sources_in_results,
        "actions": action_counts(results),
        "actions_by_state": by_state,
        "actions_by_source_state": by_source_state,
        "semantic_medians_by_state": semantic_by_state,
        "semantic_medians_by_source_state": semantic_by_source_state,
        "semantic_peak_probability_medians_by_state": semantic_confidence_by_state,
        "semantic_peak_probability_medians_by_source_state": (
            semantic_confidence_by_source_state
        ),
        "decision_latency_ms": {
            "median": statistics.median(decision_latencies),
            "min": min(decision_latencies),
            "max": max(decision_latencies),
        },
        "generation_attempts": len(attempted_rows),
        "generated_cases": generated_count,
        "generation_failures": len(failed_rows),
        "generation_failure_types": dict(
            sorted(
                Counter(
                    str(row.get("generation_error", "unknown")).split(":", 1)[0]
                    for row in failed_rows
                ).items()
            )
        ),
    }

    if generated_rows:
        summary["generation_latency_ms"] = {
            "median": statistics.median(generation_latencies),
            "min": min(generation_latencies),
            "max": max(generation_latencies),
        }
        summary["realtime_window_passes"] = realtime_pass_count
        summary["realtime_window_pass_rate"] = (
            realtime_pass_count / len(generated_rows)
        )
        summary["realtime_window_pass_rate_over_attempts"] = (
            realtime_pass_count / len(attempted_rows)
            if attempted_rows
            else 0.0
        )

    (output_dir / "results.json").write_text(
        json.dumps(
            {
                "summary": summary,
                "cases": results,
                "methodology_note": (
                    "This run reports behavior distributions, technical validity, and "
                    "realtime availability. It does not claim decision accuracy because "
                    "the corpus has no human turn-taking labels. takeover_overlay is the "
                    "only explicitly synthetic interaction state."
                ),
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print(json.dumps({"summary": summary}, ensure_ascii=False, indent=2))

    if not args.decision_only and generated_count == 0:
        raise AssertionError("no sampled scenario reached the real Aria generation stage")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
