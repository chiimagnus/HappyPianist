from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from ariautils.midi import MidiDict

from shared.aria_protocol import ControlChangeEvent, ImprovEvent, NoteEvent, ordered_events


@dataclass(frozen=True)
class MidiBuildConfig:
    ticks_per_beat: int = 480
    bpm: int = 120
    channel: int = 0


def events_to_mididict(events: list[ImprovEvent], *, config: MidiBuildConfig) -> MidiDict:
    if config.ticks_per_beat <= 0 or config.bpm <= 0:
        raise ValueError("MIDI conversion requires positive ticks_per_beat and bpm")

    tempo_us_per_beat = round(60_000_000 / config.bpm)
    ticks_per_second = config.ticks_per_beat * config.bpm / 60.0
    note_msgs: list[dict[str, Any]] = []
    pedal_msgs: list[dict[str, Any]] = []

    for event in ordered_events(events):
        if isinstance(event, NoteEvent):
            start_tick = round(event.time * ticks_per_second)
            end_tick = round((event.time + event.duration) * ticks_per_second)
            if start_tick < 0 or end_tick <= start_tick:
                raise ValueError("note event cannot be represented as a positive MIDI duration")
            note_msgs.append(
                {
                    "type": "note",
                    "data": {
                        "pitch": event.note,
                        "start": int(start_tick),
                        "end": int(end_tick),
                        "velocity": event.velocity,
                    },
                    "tick": int(start_tick),
                    "channel": config.channel,
                }
            )
        else:
            if event.controller != 64:
                raise ValueError("Aria prompt conversion only supports observed CC64")
            tick = round(event.time * ticks_per_second)
            if tick < 0:
                raise ValueError("pedal event time cannot be negative")
            pedal_msgs.append(
                {
                    "type": "pedal",
                    "data": 1 if event.value >= 64 else 0,
                    "value": event.value,
                    "tick": int(tick),
                    "channel": config.channel,
                }
            )

    return MidiDict(
        meta_msgs=[],
        tempo_msgs=[{"type": "tempo", "data": int(tempo_us_per_beat), "tick": 0}],
        pedal_msgs=pedal_msgs,
        instrument_msgs=[],
        note_msgs=note_msgs,
        ticks_per_beat=config.ticks_per_beat,
        metadata={},
    )


def _required_int(mapping: dict[str, Any], key: str, *, context: str) -> int:
    if key not in mapping:
        raise ValueError(f"{context} is missing {key!r}")
    value = mapping[key]
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{context}.{key} must be an integer")
    return value


def mididict_to_events(midi_dict: MidiDict) -> list[ImprovEvent]:
    events: list[ImprovEvent] = []

    for msg in getattr(midi_dict, "pedal_msgs", []):
        if msg.get("type") != "pedal":
            raise ValueError("unexpected non-pedal message in pedal_msgs")
        tick = _required_int(msg, "tick", context="pedal message")
        if tick < 0:
            raise ValueError("pedal tick cannot be negative")
        data = _required_int(msg, "data", context="pedal message")
        if data not in {0, 1}:
            raise ValueError("pedal data must be 0 or 1")
        value = msg.get("value")
        if value is None:
            value = 127 if data == 1 else 0
        if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= 127:
            raise ValueError("pedal value must be an integer in 0...127")
        time_s = midi_dict.tick_to_ms(tick) / 1000.0
        events.append(ControlChangeEvent(controller=64, value=value, time=time_s))

    for msg in getattr(midi_dict, "note_msgs", []):
        if msg.get("type") != "note":
            raise ValueError("unexpected non-note message in note_msgs")
        data = msg.get("data")
        if not isinstance(data, dict):
            raise ValueError("note message is missing data")
        pitch = _required_int(data, "pitch", context="note data")
        velocity = _required_int(data, "velocity", context="note data")
        start_tick = _required_int(data, "start", context="note data")
        end_tick = _required_int(data, "end", context="note data")
        if start_tick < 0 or end_tick <= start_tick:
            raise ValueError("note end must be greater than non-negative start")
        start_ms = midi_dict.tick_to_ms(start_tick)
        end_ms = midi_dict.tick_to_ms(end_tick)
        events.append(
            NoteEvent(
                note=pitch,
                velocity=velocity,
                time=start_ms / 1000.0,
                duration=(end_ms - start_ms) / 1000.0,
            )
        )

    return ordered_events(events)
