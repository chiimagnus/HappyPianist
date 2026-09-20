#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import statistics
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from mido import Message, MetaMessage, MidiFile, MidiTrack, bpm2tempo, second2tick

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
    name: str
    cutoff: float
    tail_gap: float
    ai_playback_active: bool
    acceptable_actions: tuple[str, ...]
    forced_sustain_value: int | None = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input-dir",
        type=Path,
        default=Path("aria/example-prompts"),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(".outputs/companion-decision-e2e"),
    )
    parser.add_argument("--qwen-host", default="127.0.0.1")
    parser.add_argument("--qwen-port", type=int, default=8767)
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


def percentile_cutoff(parsed: ParsedMIDI, fraction: float) -> float:
    if not parsed.notes:
        return parsed.duration
    index = min(len(parsed.notes) - 1, max(0, int(len(parsed.notes) * fraction)))
    return parsed.notes[index].start


def scenarios_for(parsed: ParsedMIDI) -> list[Scenario]:
    active_cutoff = percentile_cutoff(parsed, 0.55)
    sustain_cutoff = percentile_cutoff(parsed, 0.63)
    takeover_cutoff = percentile_cutoff(parsed, 0.72)
    last_note_end = max((n.start + n.duration for n in parsed.notes), default=parsed.duration)
    return [
        Scenario(
            "active",
            active_cutoff,
            0.05,
            False,
            ("listen", "support", "sparse", "yield"),
        ),
        Scenario("phrase_end", last_note_end, 0.75, False, ("respond",)),
        Scenario(
            "sustain_pause",
            sustain_cutoff,
            0.30,
            False,
            ("listen", "support", "sparse"),
            forced_sustain_value=127,
        ),
        Scenario("takeover", takeover_cutoff, 0.05, True, ("yield",)),
        Scenario("silence", last_note_end, 2.0, False, ("listen",), forced_sustain_value=0),
    ]


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
    now = scenario.cutoff + scenario.tail_gap
    recent_for_density = [n for n in context if n.start >= scenario.cutoff - 1.0]
    active_notes = [
        n for n in context if n.start <= now < (n.start + n.duration)
    ]
    last_note_on = max((n.start for n in context), default=None)
    last_event = max(
        [
            *(n.start + n.duration for n in context if n.start + n.duration <= now),
            *(cc.time for cc in parsed.ccs if cc.time <= now),
        ],
        default=last_note_on,
    )
    pitch_center = statistics.mean(n.note for n in context) if context else None
    tail = context[-16:]

    return {
        "protocol_version": 2,
        "input": {
            "now_timestamp_seconds": now,
            "held_notes_count": len(active_notes),
            "sustain_value": (
                scenario.forced_sustain_value
                if scenario.forced_sustain_value is not None
                else latest_sustain_value(parsed, scenario.cutoff)
            ),
            "recent_ioi_median_seconds": median_ioi(context),
            "recent_velocity_trend": velocity_trend(context),
            "recent_note_density_per_second": float(len(recent_for_density)),
            "last_user_event_timestamp_seconds": last_event,
            "last_note_on_timestamp_seconds": last_note_on,
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
        },
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


def main() -> int:
    args = parse_args()
    input_dir = args.input_dir
    if not input_dir.is_absolute():
        input_dir = Path(__file__).resolve().parents[1] / input_dir
    output_dir = args.output_dir
    if not output_dir.is_absolute():
        output_dir = Path(__file__).resolve().parents[1] / output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    qwen_url = f"http://{args.qwen_host}:{args.qwen_port}/decision"
    aria_url = f"http://{args.aria_host}:{args.aria_port}/generate"

    results: list[dict[str, Any]] = []
    generated_count = 0

    midi_paths = sorted(input_dir.glob("*.mid"))
    if not midi_paths:
        raise RuntimeError(f"no MIDI fixtures found in {input_dir}")

    for midi_path in midi_paths:
        parsed = load_midi(midi_path)
        for scenario in scenarios_for(parsed):
            decision_request = decision_payload(parsed, scenario, args.prompt_window)
            decision = post_json(qwen_url, decision_request, args.timeout)
            action = str(decision["action"])
            row: dict[str, Any] = {
                "input": midi_path.name,
                "scenario": scenario.name,
                "action": action,
                "acceptable_actions": list(scenario.acceptable_actions),
                "decision_pass": action in scenario.acceptable_actions,
                "confidence": float(decision["confidence"]),
                "decision_latency_ms": int(decision["latency_ms"]),
                "generated": False,
            }

            if action in GENERATING_ACTIONS:
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
                events = legalize_events(response.events)
                validation = validate_generated_events(request, events)
                held_notes_count = int(decision_request["input"]["held_notes_count"])
                horizon_seconds = generation_horizon_seconds(action, held_notes_count)
                realtime_note_count = sum(
                    1
                    for event in events
                    if isinstance(event, NoteEvent) and float(event.time) <= horizon_seconds
                )
                output_path = (
                    output_dir
                    / f"{midi_path.stem}-{scenario.name}-{action}.mid"
                )
                write_midi(events, output_path)
                row.update(
                    {
                        "generated": True,
                        "generation_latency_ms": response.latency_ms,
                        "output": str(output_path),
                        "realtime_horizon_seconds": horizon_seconds,
                        "realtime_note_count": realtime_note_count,
                        "realtime_window_pass": realtime_note_count > 0,
                        **validation,
                    }
                )
                generated_count += 1

            results.append(row)
            print(json.dumps(row, ensure_ascii=False), flush=True)

    decision_pass_count = sum(1 for row in results if row["decision_pass"])
    generated_rows = [row for row in results if row["generated"]]
    realtime_pass_count = sum(
        1 for row in generated_rows if row.get("realtime_window_pass")
    )
    summary = {
        "decision_cases": len(results),
        "decision_passes": decision_pass_count,
        "decision_pass_rate": decision_pass_count / len(results) if results else 0.0,
        "generated_cases": generated_count,
        "realtime_window_passes": realtime_pass_count,
        "realtime_window_pass_rate": (
            realtime_pass_count / len(generated_rows) if generated_rows else 0.0
        ),
        "inputs": len(midi_paths),
        "actions": {
            action: sum(1 for row in results if row["action"] == action)
            for action in sorted({row["action"] for row in results})
        },
    }
    (output_dir / "results.json").write_text(
        json.dumps({"summary": summary, "cases": results}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps({"summary": summary}, ensure_ascii=False, indent=2))
    if generated_count == 0:
        raise AssertionError("no scenario reached the real Aria generation stage")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
