from __future__ import annotations

import pytest
from ariautils.midi import MidiDict

from shared.aria_midi_events import MidiBuildConfig, events_to_mididict, mididict_to_events
from shared.aria_protocol import ControlChangeEvent, NoteEvent


def _midi(*, note_msgs=None, pedal_msgs=None) -> MidiDict:
    return MidiDict(
        meta_msgs=[],
        tempo_msgs=[{"type": "tempo", "data": 500000, "tick": 0}],
        pedal_msgs=list(pedal_msgs or []),
        instrument_msgs=[],
        note_msgs=list(note_msgs or []),
        ticks_per_beat=480,
        metadata={},
    )


def test_aria_midi_conversion_round_trips_valid_note_and_sustain() -> None:
    events = [
        ControlChangeEvent(controller=64, value=127, time=0.0),
        NoteEvent(note=60, velocity=90, time=0.1, duration=0.25),
    ]
    midi = events_to_mididict(events, config=MidiBuildConfig())
    decoded = mididict_to_events(midi)

    assert any(isinstance(event, ControlChangeEvent) and event.controller == 64 for event in decoded)
    note = next(event for event in decoded if isinstance(event, NoteEvent))
    assert note.note == 60
    assert note.velocity == 90
    assert note.duration > 0


def test_aria_prompt_conversion_rejects_non_sustain_cc() -> None:
    with pytest.raises(ValueError, match="only supports observed CC64"):
        events_to_mididict(
            [ControlChangeEvent(controller=7, value=100, time=0)],
            config=MidiBuildConfig(),
        )


def test_mididict_to_events_rejects_missing_note_fields_and_nonpositive_duration() -> None:
    missing_pitch = _midi(
        note_msgs=[
            {"type": "note", "data": {"velocity": 90, "start": 0, "end": 120}, "tick": 0, "channel": 0}
        ]
    )
    with pytest.raises(ValueError, match="missing 'pitch'"):
        mididict_to_events(missing_pitch)

    missing_velocity = _midi(
        note_msgs=[
            {"type": "note", "data": {"pitch": 60, "start": 0, "end": 120}, "tick": 0, "channel": 0}
        ]
    )
    with pytest.raises(ValueError, match="missing 'velocity'"):
        mididict_to_events(missing_velocity)

    zero_duration = _midi(
        note_msgs=[
            {"type": "note", "data": {"pitch": 60, "velocity": 90, "start": 120, "end": 120}, "tick": 120, "channel": 0}
        ]
    )
    with pytest.raises(ValueError, match="note end must be greater"):
        mididict_to_events(zero_duration)


def test_mididict_to_events_rejects_invalid_pedal_instead_of_repairing_it() -> None:
    invalid_pedal = _midi(
        pedal_msgs=[
            {"type": "pedal", "data": 2, "value": 127, "tick": 0, "channel": 0}
        ]
    )
    with pytest.raises(ValueError, match="pedal data must be 0 or 1"):
        mididict_to_events(invalid_pedal)
