from __future__ import annotations

import time
from typing import Any

from ..api.protocol import DialogueNote, GenerateParams
from ..media.midi_utils import NoteEvent
from .rule_backend import run_rule_improviser


def _dialogue_notes_to_note_events(notes: list[DialogueNote]) -> list[NoteEvent]:
    return [
        NoteEvent(
            note=int(note.note),
            velocity=int(note.velocity),
            time=float(note.time),
            duration=float(note.duration),
        )
        for note in notes
    ]


def _note_events_to_dialogue_notes(notes: list[NoteEvent]) -> list[DialogueNote]:
    return [
        DialogueNote(
            note=max(0, min(127, int(note.note))),
            velocity=max(1, min(127, int(note.velocity))),
            time=max(0.0, float(note.time)),
            duration=max(0.01, float(note.duration)),
        )
        for note in notes
    ]


def _max_phrase_end_sec(notes: list[DialogueNote]) -> float:
    if not notes:
        return 0.0
    return max(float(note.time + note.duration) for note in notes)


def _derive_response_length_sec(params: GenerateParams) -> float:
    sec = params.max_tokens / 64.0
    return max(2.0, min(sec, 12.0))


def generate_rule_response(
    notes: list[DialogueNote], params: GenerateParams, session_id: str | None
) -> list[DialogueNote]:
    del session_id
    reply_notes, _debug = generate_rule_response_with_debug(notes, params, session_id)
    return reply_notes


def generate_rule_response_with_debug(
    notes: list[DialogueNote], params: GenerateParams, session_id: str | None
) -> tuple[list[DialogueNote], dict[str, Any]]:
    del session_id

    input_events = _dialogue_notes_to_note_events(notes)
    response_seconds = _derive_response_length_sec(params)

    t0 = time.perf_counter()
    result = run_rule_improviser(
        input_events,
        response_seconds=response_seconds,
        style="pop",
        context_seconds=min(8.0, _max_phrase_end_sec(notes) + 1.0),
        mode="motif",
    )
    generate_ms = int((time.perf_counter() - t0) * 1000)

    reply_notes = _note_events_to_dialogue_notes(result.notes)
    debug: dict[str, Any] = {
        "engine": "rule_improviser",
        "prompt_end_sec": _max_phrase_end_sec(notes),
        "effective_response_length_sec": response_seconds,
        "generate_ms": generate_ms,
        "reply_note_count": len(reply_notes),
    }
    if result.debug:
        debug["rule_debug"] = result.debug

    return reply_notes, debug
