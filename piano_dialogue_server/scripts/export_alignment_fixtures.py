from __future__ import annotations

import json
from pathlib import Path
import sys

server_root = Path(__file__).resolve().parents[1]
if str(server_root) not in sys.path:
    sys.path.insert(0, str(server_root))

from server.api.protocol import DialogueNote, GenerateParams
from server.media.midi_generation import NoteEvent, analyze_dialogue_notes, generate_expanded_midi


def derive_response_length_sec(params: GenerateParams) -> float:
    sec = params.max_tokens / 64.0
    return max(2.0, min(sec, 30.0))


def export_deterministic_fixture(
    *,
    notes: list[DialogueNote],
    params: GenerateParams,
    session_id: str | None,
    seed: int,
    output_path: Path,
) -> None:
    analysis = analyze_dialogue_notes(notes)
    source_events = [
        NoteEvent(
            note=int(note.note),
            velocity=int(note.velocity),
            start=float(note.time),
            duration=float(note.duration),
            channel=0,
            track=0,
        )
        for note in notes
    ]

    continuation_length = derive_response_length_sec(params)
    melody, _accompaniment = generate_expanded_midi(
        source_events,
        analysis,
        mode="continue",
        extra_duration=continuation_length,
        include_source=False,
        seed=seed,
        use_model=False,
    )

    expected_notes = [
        {
            "note": int(event.note),
            "velocity": int(event.velocity),
            "time": float(event.start),
            "duration": float(event.duration),
        }
        for event in melody
    ]

    if expected_notes:
        min_time = min(note["time"] for note in expected_notes)
        if min_time > 0:
            for note in expected_notes:
                note["time"] = max(0.0, float(note["time"]) - min_time)

    payload: dict[str, object] = {
        "notes": [note.model_dump() for note in notes],
        "params": {
            "top_p": params.top_p,
            "max_tokens": params.max_tokens,
            "strategy": params.strategy,
            "seed": seed,
        },
        "session_id": session_id,
        "expected_notes": expected_notes,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def main() -> None:
    fixture_dir = (
        Path(__file__).resolve().parents[2]
        / "LonelyPianistAVPTests"
        / "Improv"
        / "DeterministicFixtures"
    )

    seed = 1234
    notes = [
        DialogueNote(note=60, velocity=92, time=0.0, duration=0.22),
        DialogueNote(note=62, velocity=92, time=0.25, duration=0.18),
        DialogueNote(note=64, velocity=92, time=0.5, duration=0.2),
        DialogueNote(note=65, velocity=92, time=0.75, duration=0.2),
        DialogueNote(note=67, velocity=92, time=1.0, duration=0.2),
        DialogueNote(note=69, velocity=92, time=1.25, duration=0.22),
        DialogueNote(note=71, velocity=92, time=1.5, duration=0.18),
        DialogueNote(note=72, velocity=92, time=1.75, duration=0.25),
    ]
    params = GenerateParams(top_p=0.95, max_tokens=256, strategy="deterministic")

    export_deterministic_fixture(
        notes=notes,
        params=params,
        session_id="fixture-1",
        seed=seed,
        output_path=fixture_dir / "fixture-1.json",
    )


if __name__ == "__main__":
    main()
