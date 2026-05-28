from __future__ import annotations

from dataclasses import dataclass

from ariautils.midi import MidiDict

from shared.protocol_v2 import ControlChangeEvent, ImprovEvent, NoteEvent, legalize_events


@dataclass(frozen=True)
class MidiBuildConfig:
    ticks_per_beat: int = 480
    bpm: int = 120
    channel: int = 0


def events_to_mididict(events: list[ImprovEvent], *, config: MidiBuildConfig) -> MidiDict:
    tempo_us_per_beat = round(60_000_000 / max(1, config.bpm))
    ticks_per_second = config.ticks_per_beat * config.bpm / 60.0

    note_msgs = []
    pedal_msgs = []

    for event in legalize_events(events):
        if isinstance(event, NoteEvent):
            start_tick = max(0, round(event.time * ticks_per_second))
            end_tick = max(start_tick, round((event.time + max(0.0, event.duration)) * ticks_per_second))
            note_msgs.append(
                {
                    "type": "note",
                    "data": {
                        "pitch": int(event.note),
                        "start": int(start_tick),
                        "end": int(end_tick),
                        "velocity": int(event.velocity),
                    },
                    "tick": int(start_tick),
                    "channel": int(config.channel),
                }
            )
        elif isinstance(event, ControlChangeEvent):
            if event.controller != 64:
                continue
            tick = max(0, round(event.time * ticks_per_second))
            pedal_msgs.append(
                {
                    "type": "pedal",
                    "data": 1 if int(event.value) >= 64 else 0,
                    "value": int(event.value),
                    "tick": int(tick),
                    "channel": int(config.channel),
                }
            )

    return MidiDict(
        meta_msgs=[],
        tempo_msgs=[{"type": "tempo", "data": int(tempo_us_per_beat), "tick": 0}],
        pedal_msgs=pedal_msgs,
        instrument_msgs=[],
        note_msgs=note_msgs,
        ticks_per_beat=int(config.ticks_per_beat),
        metadata={},
    )


def mididict_to_events(midi_dict: MidiDict) -> list[ImprovEvent]:
    events: list[ImprovEvent] = []

    for msg in getattr(midi_dict, "pedal_msgs", []):
        if msg.get("type") != "pedal":
            continue
        tick = int(msg.get("tick", 0))
        time_s = max(0.0, midi_dict.tick_to_ms(tick) / 1000.0)
        value = int(msg.get("value", 127 if int(msg.get("data", 0)) == 1 else 0))
        events.append(ControlChangeEvent(controller=64, value=value, time=time_s))

    for msg in getattr(midi_dict, "note_msgs", []):
        if msg.get("type") != "note":
            continue
        data = msg.get("data") or {}
        start_tick = int(data.get("start", msg.get("tick", 0)))
        end_tick = int(data.get("end", start_tick))
        start_ms = midi_dict.tick_to_ms(start_tick)
        end_ms = midi_dict.tick_to_ms(end_tick)
        time_s = max(0.0, start_ms / 1000.0)
        duration_s = max(0.0, (end_ms - start_ms) / 1000.0)
        events.append(
            NoteEvent(
                note=int(data.get("pitch", 60)),
                velocity=int(data.get("velocity", 64)),
                time=time_s,
                duration=duration_s,
            )
        )

    return legalize_events(events)

