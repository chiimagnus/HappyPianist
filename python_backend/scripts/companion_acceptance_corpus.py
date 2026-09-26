#!/usr/bin/env python3
from __future__ import annotations

import argparse
import bisect
import concurrent.futures
import json
import os
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

from mido import MidiFile


@dataclass(frozen=True)
class Note:
    pitch: int
    velocity: int
    start: float
    end: float


@dataclass(frozen=True)
class PedalEvent:
    time: float
    value: int


@dataclass(frozen=True)
class TimelineIndex:
    note_starts: list[float]
    note_ends: list[float]
    pedal_times: list[float]
    pedal_values: list[int]


@dataclass(frozen=True)
class Candidate:
    source: str
    file: str
    state: str
    timestamp: float
    provenance: str
    density_last_1s: int
    held_notes: int
    sustain_value: int
    previous_onset_gap: float | None
    next_onset_gap: float | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
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
        "--output",
        type=Path,
        default=Path(".outputs/companion-corpus/index.json"),
    )
    parser.add_argument("--max-per-state-per-file", type=int, default=3)
    parser.add_argument(
        "--workers",
        type=int,
        default=min(8, os.cpu_count() or 4),
        help="Number of MIDI files parsed in parallel.",
    )
    parser.add_argument(
        "--include-pop909-versions",
        action="store_true",
        help="Include POP909 versions/* MIDI in addition to the 909 main arrangements.",
    )
    return parser.parse_args()


def resolve_under_python_backend(path: Path) -> Path:
    if path.is_absolute():
        return path
    return Path(__file__).resolve().parents[1] / path


def load_midi(path: Path) -> tuple[list[Note], list[PedalEvent], float]:
    midi = MidiFile(path)
    now = 0.0
    active: dict[tuple[int, int], list[tuple[float, int]]] = defaultdict(list)
    notes: list[Note] = []
    pedals: list[PedalEvent] = []

    for message in midi:
        now += float(message.time)
        channel = int(getattr(message, "channel", 0))
        if message.type == "note_on" and message.velocity > 0:
            active[(channel, int(message.note))].append((now, int(message.velocity)))
        elif message.type == "note_off" or (
            message.type == "note_on" and message.velocity == 0
        ):
            stack = active.get((channel, int(message.note)))
            if stack:
                started_at, velocity = stack.pop(0)
                notes.append(
                    Note(
                        pitch=int(message.note),
                        velocity=velocity,
                        start=started_at,
                        end=max(started_at + 0.001, now),
                    )
                )
                if not stack:
                    active.pop((channel, int(message.note)), None)
        elif message.type == "control_change" and int(message.control) == 64:
            pedals.append(PedalEvent(time=now, value=int(message.value)))

    for (_, pitch), stack in active.items():
        for started_at, velocity in stack:
            notes.append(
                Note(
                    pitch=pitch,
                    velocity=velocity,
                    start=started_at,
                    end=max(started_at + 0.001, now),
                )
            )
    notes.sort(key=lambda note: (note.start, note.pitch, note.end))
    pedals.sort(key=lambda event: event.time)
    return notes, pedals, now


def build_timeline_index(notes: list[Note], pedals: list[PedalEvent]) -> TimelineIndex:
    return TimelineIndex(
        note_starts=sorted(note.start for note in notes),
        note_ends=sorted(note.end for note in notes),
        pedal_times=[event.time for event in pedals],
        pedal_values=[event.value for event in pedals],
    )


def pedal_value_at(index: TimelineIndex, timestamp: float) -> int:
    position = bisect.bisect_right(index.pedal_times, timestamp) - 1
    return index.pedal_values[position] if position >= 0 else 0


def settled_end_timestamp(
    index: TimelineIndex,
    performance_end: float,
) -> float | None:
    if index.pedal_values and index.pedal_values[-1] >= 64:
        return None
    last_pedal_event = index.pedal_times[-1] if index.pedal_times else 0.0
    return max(performance_end, last_pedal_event) + 0.75


def held_notes_at(index: TimelineIndex, timestamp: float) -> int:
    starts = bisect.bisect_right(index.note_starts, timestamp)
    ended = bisect.bisect_right(index.note_ends, timestamp)
    return max(0, starts - ended)


def density(index: TimelineIndex, timestamp: float) -> int:
    lower = bisect.bisect_left(index.note_starts, timestamp - 1.0)
    upper = bisect.bisect_right(index.note_starts, timestamp)
    return upper - lower


def make_candidate(
    source: str,
    relative_file: str,
    state: str,
    timestamp: float,
    provenance: str,
    index: TimelineIndex,
    onsets: list[float],
) -> Candidate:
    onset_position = bisect.bisect_right(onsets, timestamp)
    previous_onset = onsets[onset_position - 1] if onset_position > 0 else None
    next_onset = onsets[onset_position] if onset_position < len(onsets) else None
    prev_gap = timestamp - previous_onset if previous_onset is not None else None
    next_gap = next_onset - timestamp if next_onset is not None else None
    return Candidate(
        source=source,
        file=relative_file,
        state=state,
        timestamp=round(timestamp, 6),
        provenance=provenance,
        density_last_1s=density(index, timestamp),
        held_notes=held_notes_at(index, timestamp),
        sustain_value=pedal_value_at(index, timestamp),
        previous_onset_gap=None if prev_gap is None else round(prev_gap, 6),
        next_onset_gap=None if next_gap is None else round(next_gap, 6),
    )


def validate_candidate(candidate: Candidate) -> None:
    if candidate.state in {"active_dense", "takeover_overlay"}:
        if candidate.density_last_1s < 8:
            raise AssertionError(f"{candidate.state} density invariant failed: {candidate}")
        if candidate.next_onset_gap is None or candidate.next_onset_gap > 0.20:
            raise AssertionError(f"{candidate.state} next-onset invariant failed: {candidate}")
        return

    if candidate.state == "active_sparse":
        if candidate.density_last_1s > 4:
            raise AssertionError(f"active_sparse density invariant failed: {candidate}")
        if (
            candidate.next_onset_gap is None
            or candidate.next_onset_gap < 0.05
            or candidate.next_onset_gap > 0.55
        ):
            raise AssertionError(f"active_sparse next-onset invariant failed: {candidate}")
        return

    if candidate.state == "sustain_pause":
        if candidate.sustain_value < 64:
            raise AssertionError(f"sustain_pause pedal invariant failed: {candidate}")
        return

    if candidate.state == "natural_silence":
        if candidate.held_notes != 0 or candidate.sustain_value >= 64:
            raise AssertionError(f"natural_silence state invariant failed: {candidate}")
        if (
            candidate.previous_onset_gap is None
            or candidate.previous_onset_gap < 0.60
            or candidate.next_onset_gap is None
            or candidate.next_onset_gap < 0.60
        ):
            raise AssertionError(f"natural_silence gap invariant failed: {candidate}")
        return

    if candidate.state == "settled_end":
        if (
            candidate.held_notes != 0
            or candidate.sustain_value >= 64
            or candidate.next_onset_gap is not None
            or candidate.previous_onset_gap is None
            or candidate.previous_onset_gap < 0.50
        ):
            raise AssertionError(f"settled_end invariant failed: {candidate}")
        return

    raise AssertionError(f"unsupported candidate state: {candidate.state}")


def spaced_take(
    timestamps: Iterable[float],
    *,
    limit: int,
    separation: float = 2.0,
) -> list[float]:
    picked: list[float] = []
    for timestamp in timestamps:
        if not picked or timestamp - picked[-1] >= separation:
            picked.append(timestamp)
            if len(picked) >= limit:
                break
    return picked


def extract_candidates(
    source: str,
    relative_file: str,
    notes: list[Note],
    pedals: list[PedalEvent],
    *,
    max_per_state: int,
) -> list[Candidate]:
    if not notes:
        return []

    index = build_timeline_index(notes, pedals)
    onsets = sorted(set(index.note_starts))
    if len(onsets) < 2:
        return []

    result: list[Candidate] = []

    dense_times: list[float] = []
    sparse_times: list[float] = []
    for onset_index, timestamp in enumerate(onsets[:-1]):
        next_gap = onsets[onset_index + 1] - timestamp
        recent_density = density(index, timestamp)
        if next_gap <= 0.20 and recent_density >= 8:
            candidate_time = timestamp + min(0.03, next_gap / 3)
            candidate_position = bisect.bisect_right(onsets, candidate_time)
            candidate_next = (
                onsets[candidate_position]
                if candidate_position < len(onsets)
                else None
            )
            if (
                candidate_next is not None
                and candidate_next - candidate_time <= 0.20
                and density(index, candidate_time) >= 8
            ):
                dense_times.append(candidate_time)
        if 0.10 <= next_gap <= 0.55 and recent_density <= 4:
            candidate_time = timestamp + min(0.08, next_gap / 3)
            candidate_position = bisect.bisect_right(onsets, candidate_time)
            candidate_next = (
                onsets[candidate_position]
                if candidate_position < len(onsets)
                else None
            )
            if (
                candidate_next is not None
                and 0.05 <= candidate_next - candidate_time <= 0.55
                and density(index, candidate_time) <= 4
            ):
                sparse_times.append(candidate_time)

    for timestamp in spaced_take(dense_times, limit=max_per_state):
        result.append(
            make_candidate(
                source,
                relative_file,
                "active_dense",
                timestamp,
                "natural_midi",
                index,
                onsets,
            )
        )

    for timestamp in spaced_take(sparse_times, limit=max_per_state):
        result.append(
            make_candidate(
                source,
                relative_file,
                "active_sparse",
                timestamp,
                "natural_midi",
                index,
                onsets,
            )
        )

    sustain_times: list[float] = []
    natural_silence_times: list[float] = []
    for previous, following in zip(onsets, onsets[1:]):
        gap = following - previous
        if 0.30 <= gap <= 0.90:
            timestamp = previous + min(0.40, gap * 0.55)
            if pedal_value_at(index, timestamp) >= 64:
                sustain_times.append(timestamp)

        if gap >= 1.20:
            timestamp = previous + min(0.90, gap * 0.5)
            if (
                pedal_value_at(index, timestamp) < 64
                and held_notes_at(index, timestamp) == 0
            ):
                natural_silence_times.append(timestamp)

    for timestamp in spaced_take(sustain_times, limit=max_per_state):
        result.append(
            make_candidate(
                source,
                relative_file,
                "sustain_pause",
                timestamp,
                "natural_midi",
                index,
                onsets,
            )
        )

    for timestamp in spaced_take(natural_silence_times, limit=max_per_state):
        result.append(
            make_candidate(
                source,
                relative_file,
                "natural_silence",
                timestamp,
                "natural_midi",
                index,
                onsets,
            )
        )

    performance_end = max(note.end for note in notes)
    final_timestamp = settled_end_timestamp(index, performance_end)
    if final_timestamp is not None:
        result.append(
            make_candidate(
                source,
                relative_file,
                "settled_end",
                final_timestamp,
                "natural_settled_boundary",
                index,
                onsets,
            )
        )

    for dense_timestamp in spaced_take(dense_times, limit=max_per_state):
        result.append(
            make_candidate(
                source,
                relative_file,
                "takeover_overlay",
                dense_timestamp,
                "synthetic_ai_playback_overlay_on_natural_user_midi",
                index,
                onsets,
            )
        )

    for candidate in result:
        validate_candidate(candidate)

    return result


def maestro_files(root: Path) -> list[Path]:
    return sorted([*root.rglob("*.mid"), *root.rglob("*.midi")])


def pop909_files(root: Path, include_versions: bool) -> list[Path]:
    files: list[Path] = []
    for directory in sorted(path for path in root.iterdir() if path.is_dir()):
        main = directory / f"{directory.name}.mid"
        if main.exists():
            files.append(main)
        if include_versions:
            versions = directory / "versions"
            if versions.exists():
                files.extend(sorted(versions.glob("*.mid")))
    return files


def process_corpus_file(
    task: tuple[str, str, str, int],
) -> tuple[list[Candidate], dict[str, str] | None]:
    source, root_text, path_text, max_per_state = task
    root = Path(root_text)
    path = Path(path_text)
    try:
        notes, pedals, _ = load_midi(path)
        candidates = extract_candidates(
            source,
            str(path.relative_to(root)).replace("\\", "/"),
            notes,
            pedals,
            max_per_state=max_per_state,
        )
        return candidates, None
    except Exception as error:
        return [], {
            "source": source,
            "file": str(path),
            "error": f"{type(error).__name__}: {error}",
        }


def main() -> int:
    args = parse_args()
    maestro_root = resolve_under_python_backend(args.maestro_root)
    pop909_root = resolve_under_python_backend(args.pop909_root)
    output = resolve_under_python_backend(args.output)

    corpus = [
        ("maestro", maestro_root, maestro_files(maestro_root)),
        (
            "pop909",
            pop909_root,
            pop909_files(pop909_root, args.include_pop909_versions),
        ),
    ]

    all_candidates: list[Candidate] = []
    file_stats: dict[str, int] = {}
    errors: list[dict[str, str]] = []
    tasks: list[tuple[str, str, str, int]] = []

    for source, root, files in corpus:
        file_stats[source] = len(files)
        tasks.extend(
            (source, str(root), str(path), args.max_per_state_per_file)
            for path in files
        )

    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as executor:
        for candidates, error in executor.map(
            process_corpus_file,
            tasks,
            chunksize=8,
        ):
            all_candidates.extend(candidates)
            if error is not None:
                errors.append(error)

    state_counts = Counter(candidate.state for candidate in all_candidates)
    state_file_counts: dict[str, int] = {}
    for state in state_counts:
        state_file_counts[state] = len(
            {
                (candidate.source, candidate.file)
                for candidate in all_candidates
                if candidate.state == state
            }
        )

    payload = {
        "methodology": {
            "active_dense": "Natural MIDI: <=200ms to next onset and >=8 onsets in previous 1s.",
            "active_sparse": "Natural MIDI: 100-550ms to next onset and <=4 onsets in previous 1s.",
            "sustain_pause": "Natural MIDI: 300-900ms onset gap and actual CC64 >=64 during the gap.",
            "natural_silence": "Natural MIDI: >=1.2s onset gap, pedal up and no physically held note at sampled time.",
            "settled_end": (
                "Natural settled boundary: 750ms after the final physical note end and "
                "the final sustain-pedal event. Files whose final pedal state is still down "
                "do not receive this state."
            ),
            "takeover_overlay": "Synthetic AI-playback flag over a naturally dense user-performance window; not claimed as corpus ground truth.",
        },
        "files": file_stats,
        "candidate_counts": dict(sorted(state_counts.items())),
        "files_with_state": dict(sorted(state_file_counts.items())),
        "errors": errors,
        "candidates": [asdict(candidate) for candidate in all_candidates],
    }

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
        newline="\n",
    )

    print(
        json.dumps(
            {
                "files": file_stats,
                "candidate_counts": dict(sorted(state_counts.items())),
                "files_with_state": dict(sorted(state_file_counts.items())),
                "errors": len(errors),
                "output": str(output),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
