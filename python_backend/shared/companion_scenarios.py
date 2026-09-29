from __future__ import annotations

import random
import statistics
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from mido import MidiFile


PROJECTION_VERSION = "duet-phrase-buffer-v1"
LOOKBACK_SECONDS = 4.0
IOI_WINDOW_SECONDS = 2.4
DENSITY_WINDOW_SECONDS = 1.2


@dataclass(frozen=True)
class ParsedNote:
    note: int
    velocity: int
    start: float
    duration: float

    @property
    def end(self) -> float:
        return self.start + self.duration


@dataclass(frozen=True)
class ParsedCC:
    controller: int
    value: int
    time: float


@dataclass(frozen=True)
class ProjectionEvent:
    time: float
    sequence: int
    kind: str
    note: int | None = None
    velocity: int | None = None
    value: int | None = None


@dataclass(frozen=True)
class ParsedMIDI:
    notes: list[ParsedNote]
    ccs: list[ParsedCC]
    projection_events: list[ProjectionEvent]
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


def resolve_under_python_backend(path: Path) -> Path:
    if path.is_absolute():
        return path
    return Path(__file__).resolve().parents[1] / path


def load_midi(path: Path) -> ParsedMIDI:
    midi = MidiFile(path)
    current_time = 0.0
    active: dict[tuple[int, int], list[tuple[float, int]]] = {}
    notes: list[ParsedNote] = []
    ccs: list[ParsedCC] = []
    projection_events: list[ProjectionEvent] = []
    sequence = 0

    for message in midi:
        current_time += float(message.time)
        channel = int(getattr(message, "channel", 0))
        if message.type == "note_on" and message.velocity > 0:
            projection_events.append(
                ProjectionEvent(
                    time=current_time,
                    sequence=sequence,
                    kind="note_on",
                    note=int(message.note),
                    velocity=int(message.velocity),
                )
            )
            sequence += 1
            active.setdefault((channel, int(message.note)), []).append(
                (current_time, int(message.velocity))
            )
        elif message.type == "note_off" or (
            message.type == "note_on" and message.velocity == 0
        ):
            projection_events.append(
                ProjectionEvent(
                    time=current_time,
                    sequence=sequence,
                    kind="note_off",
                    note=int(message.note),
                )
            )
            sequence += 1
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
            controller = int(message.control)
            value = int(message.value)
            ccs.append(
                ParsedCC(
                    controller=controller,
                    value=value,
                    time=current_time,
                )
            )
            if controller == 64:
                projection_events.append(
                    ProjectionEvent(
                        time=current_time,
                        sequence=sequence,
                        kind="cc64",
                        value=value,
                    )
                )
                sequence += 1

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

    notes.sort(key=lambda item: (item.start, item.note, item.end))
    ccs.sort(key=lambda item: item.time)
    return ParsedMIDI(
        notes=notes,
        ccs=ccs,
        projection_events=projection_events,
        duration=current_time,
    )


def notes_before(parsed: ParsedMIDI, cutoff: float, window: float) -> list[ParsedNote]:
    start = cutoff - window
    return [
        note
        for note in parsed.notes
        if note.start <= cutoff and note.end >= start
    ]


def project_qwen_state(
    parsed: ParsedMIDI,
    cutoff: float,
    *,
    is_ai_playback_active: bool,
    user_note_on_since_ai_playback_started: bool,
) -> dict[str, Any]:
    sustain = 0
    open_notes: dict[int, int] = {}
    sustained_notes: dict[int, int] = {}
    note_starts: list[float] = []

    for event in parsed.projection_events:
        if event.time > cutoff:
            break
        if event.kind == "note_on":
            if event.note is None or event.velocity is None:
                raise ValueError("note_on projection event is missing note or velocity")
            note_starts.append(event.time)
            open_notes.pop(event.note, None)
            sustained_notes.pop(event.note, None)
            open_notes[event.note] = event.velocity
        elif event.kind == "note_off":
            if event.note is None:
                raise ValueError("note_off projection event is missing note")
            velocity = open_notes.pop(event.note, None)
            if velocity is not None and sustain >= 64:
                sustained_notes[event.note] = velocity
        elif event.kind == "cc64":
            if event.value is None:
                raise ValueError("cc64 projection event is missing value")
            was_down = sustain >= 64
            sustain = event.value
            if was_down and sustain < 64:
                sustained_notes.clear()
        else:
            raise ValueError(f"unsupported projection event kind: {event.kind}")

    recent_ioi_starts = [
        start for start in note_starts if start >= cutoff - IOI_WINDOW_SECONDS
    ]
    iois = [
        current - previous
        for previous, current in zip(recent_ioi_starts, recent_ioi_starts[1:])
    ]
    density_count = sum(
        1 for start in note_starts if start >= cutoff - DENSITY_WINDOW_SECONDS
    )
    last_note_on = note_starts[-1] if note_starts else None
    return {
        "held_notes_count": len(set(open_notes) | set(sustained_notes)),
        "sustain_value": sustain,
        "recent_ioi_median_seconds": statistics.median(iois) if iois else None,
        "recent_note_density_per_second": density_count / DENSITY_WINDOW_SECONDS,
        "seconds_since_last_note_on": (
            None if last_note_on is None else max(0.0, cutoff - last_note_on)
        ),
        "is_ai_playback_active": is_ai_playback_active,
        "user_note_on_since_ai_playback_started": user_note_on_since_ai_playback_started,
    }


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
            candidates_by_file: dict[str, list[dict[str, Any]]] = {}
            for candidate in candidates:
                candidates_by_file.setdefault(str(candidate["file"]), []).append(candidate)
            if len(candidates_by_file) < cases_per_state_per_source:
                raise RuntimeError(
                    f"insufficient independent files for {source}/{state}: "
                    f"need {cases_per_state_per_source}, have {len(candidates_by_file)}"
                )
            selected_files = rng.sample(
                sorted(candidates_by_file),
                cases_per_state_per_source,
            )
            for file in selected_files:
                candidate = rng.choice(candidates_by_file[file])
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
