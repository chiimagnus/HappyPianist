#!/usr/bin/env python3
from __future__ import annotations

import argparse
import bisect
import concurrent.futures
import json
import os
import sys
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

PYTHON_BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(PYTHON_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(PYTHON_BACKEND_ROOT))

from shared.companion_scenarios import (
    DENSITY_WINDOW_SECONDS,
    PROJECTION_VERSION,
    ParsedMIDI,
    load_midi,
    project_qwen_state,
    resolve_under_python_backend,
)


@dataclass(frozen=True)
class Candidate:
    source: str
    file: str
    state: str
    timestamp: float
    provenance: str
    recent_note_density_per_second: float
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
    parser.add_argument("--workers", type=int, default=min(8, os.cpu_count() or 4))
    parser.add_argument("--include-pop909-versions", action="store_true")
    return parser.parse_args()


def _onsets(parsed: ParsedMIDI) -> list[float]:
    return sorted({note.start for note in parsed.notes})


def _density(note_starts: list[float], timestamp: float) -> float:
    lower = bisect.bisect_left(note_starts, timestamp - DENSITY_WINDOW_SECONDS)
    upper = bisect.bisect_right(note_starts, timestamp)
    return (upper - lower) / DENSITY_WINDOW_SECONDS


def _pedal_value(parsed: ParsedMIDI, timestamp: float) -> int:
    value = 0
    for event in parsed.ccs:
        if event.time > timestamp:
            break
        if event.controller == 64:
            value = event.value
    return value


def make_candidate(
    source: str,
    relative_file: str,
    state: str,
    timestamp: float,
    provenance: str,
    parsed: ParsedMIDI,
    onsets: list[float],
) -> Candidate:
    position = bisect.bisect_right(onsets, timestamp)
    previous = onsets[position - 1] if position > 0 else None
    following = onsets[position] if position < len(onsets) else None
    projected = project_qwen_state(
        parsed,
        timestamp,
        is_ai_playback_active=state == "takeover_overlay",
        user_note_on_since_ai_playback_started=state == "takeover_overlay",
    )
    return Candidate(
        source=source,
        file=relative_file,
        state=state,
        timestamp=round(timestamp, 6),
        provenance=provenance,
        recent_note_density_per_second=round(
            float(projected["recent_note_density_per_second"]), 6
        ),
        held_notes=int(projected["held_notes_count"]),
        sustain_value=int(projected["sustain_value"]),
        previous_onset_gap=(
            None if previous is None else round(timestamp - previous, 6)
        ),
        next_onset_gap=(
            None if following is None else round(following - timestamp, 6)
        ),
    )


def validate_candidate(candidate: Candidate) -> None:
    if candidate.state in {"active_dense", "takeover_overlay"}:
        if candidate.recent_note_density_per_second < 8.0:
            raise AssertionError(f"{candidate.state} density invariant failed: {candidate}")
        if candidate.next_onset_gap is None or candidate.next_onset_gap > 0.20:
            raise AssertionError(f"{candidate.state} next-onset invariant failed: {candidate}")
        return
    if candidate.state == "active_sparse":
        if candidate.recent_note_density_per_second > 4.0:
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
    timestamps: Iterable[float], *, limit: int, separation: float = 2.0
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
    parsed: ParsedMIDI,
    *,
    max_per_state: int,
) -> list[Candidate]:
    if not parsed.notes:
        return []
    onsets = _onsets(parsed)
    if len(onsets) < 2:
        return []
    note_starts = sorted(note.start for note in parsed.notes)

    dense_times: list[float] = []
    sparse_times: list[float] = []
    sustain_times: list[float] = []
    silence_times: list[float] = []
    for index, timestamp in enumerate(onsets[:-1]):
        following = onsets[index + 1]
        gap = following - timestamp
        dense_candidate = timestamp + min(0.03, gap / 3)
        dense_next = following - dense_candidate
        if dense_next <= 0.20 and _density(note_starts, dense_candidate) >= 8.0:
            dense_times.append(dense_candidate)

        sparse_candidate = timestamp + min(0.08, gap / 3)
        sparse_next = following - sparse_candidate
        if (
            0.05 <= sparse_next <= 0.55
            and _density(note_starts, sparse_candidate) <= 4.0
        ):
            sparse_times.append(sparse_candidate)

        if 0.30 <= gap <= 0.90:
            candidate = timestamp + min(0.40, gap * 0.55)
            if _pedal_value(parsed, candidate) >= 64:
                sustain_times.append(candidate)

        if gap >= 1.20:
            candidate = timestamp + min(0.90, gap * 0.5)
            projected = project_qwen_state(
                parsed,
                candidate,
                is_ai_playback_active=False,
                user_note_on_since_ai_playback_started=False,
            )
            if (
                projected["sustain_value"] < 64
                and projected["held_notes_count"] == 0
            ):
                silence_times.append(candidate)

    result: list[Candidate] = []
    for state, times, provenance in (
        ("active_dense", dense_times, "natural_midi"),
        ("active_sparse", sparse_times, "natural_midi"),
        ("sustain_pause", sustain_times, "natural_midi"),
        ("natural_silence", silence_times, "natural_midi"),
        (
            "takeover_overlay",
            dense_times,
            "synthetic_ai_playback_overlay_on_natural_user_midi",
        ),
    ):
        for timestamp in spaced_take(times, limit=max_per_state):
            candidate = make_candidate(
                source,
                relative_file,
                state,
                timestamp,
                provenance,
                parsed,
                onsets,
            )
            validate_candidate(candidate)
            result.append(candidate)

    final_pedal = _pedal_value(parsed, parsed.duration)
    if final_pedal < 64:
        performance_end = max(note.end for note in parsed.notes)
        last_pedal_time = max(
            (event.time for event in parsed.ccs if event.controller == 64),
            default=0.0,
        )
        final_timestamp = max(performance_end, last_pedal_time) + 0.75
        candidate = make_candidate(
            source,
            relative_file,
            "settled_end",
            final_timestamp,
            "natural_settled_boundary",
            parsed,
            onsets,
        )
        validate_candidate(candidate)
        result.append(candidate)

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
        parsed = load_midi(path)
        candidates = extract_candidates(
            source,
            str(path.relative_to(root)).replace("\\", "/"),
            parsed,
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
        ("pop909", pop909_root, pop909_files(pop909_root, args.include_pop909_versions)),
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
        for candidates, error in executor.map(process_corpus_file, tasks, chunksize=8):
            all_candidates.extend(candidates)
            if error is not None:
                errors.append(error)

    state_counts = Counter(candidate.state for candidate in all_candidates)
    state_file_counts = {
        state: len(
            {
                (candidate.source, candidate.file)
                for candidate in all_candidates
                if candidate.state == state
            }
        )
        for state in state_counts
    }
    payload = {
        "projection_version": PROJECTION_VERSION,
        "methodology": {
            "active_dense": "Natural MIDI: <=200ms to next onset and product-projected density >=8 notes/s over 1.2s.",
            "active_sparse": "Natural MIDI: 50-550ms to next onset and product-projected density <=4 notes/s over 1.2s.",
            "sustain_pause": "Natural MIDI: 300-900ms onset gap and actual CC64 >=64 during the gap.",
            "natural_silence": "Natural MIDI: >=1.2s onset gap, pedal up and no product-projected sounding note.",
            "settled_end": "750ms after final physical note end/final pedal event, with pedal up and no sounding note.",
            "takeover_overlay": "AI-playback/post-start-note-on flags over a naturally dense user-performance window; not corpus turn-taking ground truth.",
        },
        "files": file_stats,
        "candidate_counts": dict(sorted(state_counts.items())),
        "files_with_state": dict(sorted(state_file_counts.items())),
        "errors": errors,
        "candidates": [asdict(candidate) for candidate in all_candidates],
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
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
