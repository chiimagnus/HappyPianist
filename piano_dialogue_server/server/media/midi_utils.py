from __future__ import annotations

import math
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import mido
import numpy as np


DEFAULT_TEMPO = 500_000
DEFAULT_TIME_SIGNATURE_NUMERATOR = 4
DEFAULT_TIME_SIGNATURE_DENOMINATOR = 4
SAMPLE_RATE = 44_100

_SYNTH_INSTANCE: Any = None
_SYNTH_SFID: int = -1


def _get_synth() -> tuple[Any, int] | tuple[None, int]:
    """Return a cached (fluidsynth.Synth, sfid) pair, or (None, -1)."""
    global _SYNTH_INSTANCE, _SYNTH_SFID  # noqa: PLW0603
    if _SYNTH_INSTANCE is not None:
        return _SYNTH_INSTANCE, _SYNTH_SFID

    base = Path(__file__).resolve().parent
    candidates = [
        base / "soundfonts" / "SalC5Light2.sf2",
        base / "LonelyPianist" / "LonelyPianistAVP" / "Resources"
        / "lonelypainist-SALC5-Light-SF-v2_7" / "SalC5Light2.sf2",
        base / "LonelyPianistAVP" / "lonelypainist-SALC5-Light-SF-v2_7" / "SalC5Light2.sf2",
        base / "LonelyPianist.archive-copy" / "lonelypainist-SALC5-Light-SF-v2_7" / "SalC5Light2.sf2",
    ]
    sf_path: Path | None = None
    for candidate in candidates:
        if candidate.exists():
            sf_path = candidate
            break
    if sf_path is None:
        return None, -1

    try:
        import fluidsynth as _fluidsynth  # pyfluidsynth

        synth = _fluidsynth.Synth(samplerate=float(SAMPLE_RATE))
        sfid = synth.sfload(str(sf_path))
        synth.program_select(0, sfid, 0, 0)
        _SYNTH_INSTANCE = synth
        _SYNTH_SFID = sfid
        return synth, sfid
    except Exception:
        return None, -1


@dataclass(frozen=True)
class MidiMeta:
    ticks_per_beat: int
    tempo: int
    bpm: float
    numerator: int
    denominator: int
    ticks_per_measure: int
    total_ticks: int
    total_measures: int
    duration_seconds: float


@dataclass(frozen=True)
class NoteEvent:
    note: int
    velocity: int
    time: float
    duration: float

    def as_dict(self) -> dict[str, Any]:
        return {
            "note": self.note,
            "velocity": self.velocity,
            "time": self.time,
            "duration": self.duration,
        }


@dataclass(frozen=True)
class ClipResult:
    notes: list[NoteEvent]
    meta: MidiMeta
    start_measure: int
    end_measure: int
    start_tick: int
    end_tick: int
    duration_seconds: float


def load_midi_meta(path: Path) -> MidiMeta:
    midi = mido.MidiFile(str(path))
    tempo = DEFAULT_TEMPO
    numerator = DEFAULT_TIME_SIGNATURE_NUMERATOR
    denominator = DEFAULT_TIME_SIGNATURE_DENOMINATOR
    total_ticks = 0

    for track in midi.tracks:
        absolute_tick = 0
        for message in track:
            absolute_tick += int(message.time)
            total_ticks = max(total_ticks, absolute_tick)
            if message.type == "set_tempo":
                tempo = int(message.tempo)
            elif message.type == "time_signature":
                numerator = int(message.numerator)
                denominator = int(message.denominator)

    ticks_per_measure = int(round(midi.ticks_per_beat * numerator * 4 / denominator))
    if ticks_per_measure <= 0:
        ticks_per_measure = midi.ticks_per_beat * 4
    total_measures = max(1, int(math.ceil(total_ticks / ticks_per_measure)))
    duration_seconds = float(mido.tick2second(total_ticks, midi.ticks_per_beat, tempo))
    bpm = float(mido.tempo2bpm(tempo))

    return MidiMeta(
        ticks_per_beat=midi.ticks_per_beat,
        tempo=tempo,
        bpm=bpm,
        numerator=numerator,
        denominator=denominator,
        ticks_per_measure=ticks_per_measure,
        total_ticks=total_ticks,
        total_measures=total_measures,
        duration_seconds=duration_seconds,
    )


def clip_midi_by_measures(path: Path, start_measure: int, end_measure: int) -> ClipResult:
    if start_measure < 1:
        raise ValueError("start_measure must be >= 1")
    if end_measure < start_measure:
        raise ValueError("end_measure must be >= start_measure")

    midi = mido.MidiFile(str(path))
    meta = load_midi_meta(path)
    start_tick = int((start_measure - 1) * meta.ticks_per_measure)
    end_tick = int(end_measure * meta.ticks_per_measure)
    clip_duration_ticks = max(0, end_tick - start_tick)
    clip_duration_seconds = float(mido.tick2second(clip_duration_ticks, meta.ticks_per_beat, meta.tempo))

    notes: list[NoteEvent] = []
    active: dict[tuple[int, int], list[tuple[int, int]]] = {}

    for track in midi.tracks:
        absolute_tick = 0
        for message in track:
            absolute_tick += int(message.time)
            if message.type not in {"note_on", "note_off"}:
                continue

            channel = int(getattr(message, "channel", 0))
            note = int(message.note)
            velocity = int(getattr(message, "velocity", 0))
            key = (channel, note)

            if message.type == "note_on" and velocity > 0:
                active.setdefault(key, []).append((absolute_tick, velocity))
                continue

            starts = active.get(key)
            if not starts:
                continue
            note_start_tick, note_velocity = starts.pop(0)
            if not starts:
                active.pop(key, None)

            note_end_tick = absolute_tick
            if note_end_tick <= start_tick or note_start_tick >= end_tick:
                continue

            clipped_start = max(note_start_tick, start_tick)
            clipped_end = min(note_end_tick, end_tick)
            duration_ticks = clipped_end - clipped_start
            if duration_ticks <= 0:
                continue

            start_seconds = float(
                mido.tick2second(clipped_start - start_tick, meta.ticks_per_beat, meta.tempo)
            )
            duration_seconds = float(mido.tick2second(duration_ticks, meta.ticks_per_beat, meta.tempo))
            notes.append(
                NoteEvent(
                    note=max(0, min(127, note)),
                    velocity=max(1, min(127, note_velocity)),
                    time=start_seconds,
                    duration=max(0.01, duration_seconds),
                )
            )

    notes.sort(key=lambda event: (event.time, event.note, event.duration))
    return ClipResult(
        notes=notes,
        meta=meta,
        start_measure=start_measure,
        end_measure=end_measure,
        start_tick=start_tick,
        end_tick=end_tick,
        duration_seconds=clip_duration_seconds,
    )


def read_midi_notes(path: Path) -> list[NoteEvent]:
    meta = load_midi_meta(path)
    midi = mido.MidiFile(str(path))
    notes: list[NoteEvent] = []
    active: dict[tuple[int, int], list[tuple[int, int]]] = {}

    for track in midi.tracks:
        absolute_tick = 0
        for message in track:
            absolute_tick += int(message.time)
            if message.type not in {"note_on", "note_off"}:
                continue

            channel = int(getattr(message, "channel", 0))
            note = int(message.note)
            velocity = int(getattr(message, "velocity", 0))
            key = (channel, note)

            if message.type == "note_on" and velocity > 0:
                active.setdefault(key, []).append((absolute_tick, velocity))
                continue

            starts = active.get(key)
            if not starts:
                continue
            note_start_tick, note_velocity = starts.pop(0)
            if not starts:
                active.pop(key, None)

            duration_ticks = absolute_tick - note_start_tick
            if duration_ticks <= 0:
                continue

            notes.append(
                NoteEvent(
                    note=max(0, min(127, note)),
                    velocity=max(1, min(127, note_velocity)),
                    time=float(mido.tick2second(note_start_tick, meta.ticks_per_beat, meta.tempo)),
                    duration=max(0.01, float(mido.tick2second(duration_ticks, meta.ticks_per_beat, meta.tempo))),
                )
            )

    return sorted(notes, key=lambda event: (event.time, event.note, event.duration))


def write_notes_to_midi(
    notes: list[NoteEvent],
    path: Path,
    *,
    tempo: int = DEFAULT_TEMPO,
    ticks_per_beat: int = 480,
    numerator: int = DEFAULT_TIME_SIGNATURE_NUMERATOR,
    denominator: int = DEFAULT_TIME_SIGNATURE_DENOMINATOR,
) -> None:
    midi = mido.MidiFile(ticks_per_beat=ticks_per_beat)
    track = mido.MidiTrack()
    midi.tracks.append(track)
    track.append(mido.MetaMessage("set_tempo", tempo=tempo, time=0))
    track.append(
        mido.MetaMessage(
            "time_signature",
            numerator=numerator,
            denominator=denominator,
            time=0,
        )
    )

    events: list[tuple[float, int, mido.Message]] = []
    for note in notes:
        start = max(0.0, float(note.time))
        end = start + max(0.01, float(note.duration))
        pitch = max(0, min(127, int(note.note)))
        velocity = max(1, min(127, int(note.velocity)))
        events.append((start, 1, mido.Message("note_on", note=pitch, velocity=velocity, channel=0, time=0)))
        events.append((end, 0, mido.Message("note_off", note=pitch, velocity=0, channel=0, time=0)))

    events.sort(key=lambda item: (item[0], item[1], getattr(item[2], "note", 0)))
    last_time = 0.0
    for event_time, _, message in events:
        delta_seconds = max(0.0, event_time - last_time)
        message.time = int(round(mido.second2tick(delta_seconds, ticks_per_beat, tempo)))
        track.append(message)
        last_time = event_time

    path.parent.mkdir(parents=True, exist_ok=True)
    midi.save(str(path))


def _synthesize_fluidsynth(
    notes: list[NoteEvent],
    path: Path,
    *,
    minimum_duration: float,
    tail_seconds: float,
    sample_rate: int,
) -> float | None:
    """Render notes via in-process FluidSynth + SoundFont.  Returns duration on success, None on failure."""
    synth, sfid = _get_synth()
    if synth is None:
        return None

    if notes:
        end_time = max(note.time + note.duration for note in notes)
    else:
        end_time = minimum_duration
    duration = max(minimum_duration, end_time + tail_seconds)

    try:
        total_samples = int(math.ceil(duration * sample_rate))

        # Schedule note events sorted by time
        events: list[tuple[float, bool, int, int]] = []  # (time, is_on, note, velocity)
        for note in notes:
            events.append((max(0.0, note.time), True, note.note, note.velocity))
            events.append((max(0.0, note.time + note.duration), False, note.note, 0))
        events.sort(key=lambda e: (e[0], e[1]))  # note-offs before note-ons at same time

        # Render in chunks between events
        audio_chunks: list[np.ndarray] = []
        current_sample = 0

        for event_time, is_on, pitch, velocity in events:
            target_sample = min(total_samples, int(round(event_time * sample_rate)))
            if target_sample > current_sample:
                chunk_len = target_sample - current_sample
                raw = synth.get_samples(chunk_len)
                audio_chunks.append(np.frombuffer(raw, dtype=np.int16).copy())
                current_sample = target_sample

            if is_on:
                synth.noteon(0, max(0, min(127, pitch)), max(1, min(127, velocity)))
            else:
                synth.noteoff(0, max(0, min(127, pitch)))

        # Render remaining tail
        if current_sample < total_samples:
            raw = synth.get_samples(total_samples - current_sample)
            audio_chunks.append(np.frombuffer(raw, dtype=np.int16).copy())

        # Turn off all notes to reset state
        synth.system_reset()
        synth.program_select(0, sfid, 0, 0)

        audio = np.concatenate(audio_chunks) if audio_chunks else np.zeros(2, dtype=np.int16)
        # FluidSynth outputs stereo interleaved (L, R, L, R, ...)
        # Mix down to mono
        stereo = audio.reshape(-1, 2)
        mono = ((stereo[:, 0].astype(np.int32) + stereo[:, 1].astype(np.int32)) // 2).astype(np.int16)

        path.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(path), "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(sample_rate)
            wf.writeframes(mono.tobytes())

        return duration
    except Exception:
        return None


def _synthesize_sine(
    notes: list[NoteEvent],
    path: Path,
    *,
    minimum_duration: float,
    tail_seconds: float,
    sample_rate: int,
) -> float:
    """Fallback additive sine-wave synthesis."""
    if notes:
        end_time = max(note.time + note.duration for note in notes)
    else:
        end_time = minimum_duration
    duration = max(minimum_duration, end_time + tail_seconds)
    sample_count = max(1, int(math.ceil(duration * sample_rate)))
    audio = np.zeros(sample_count, dtype=np.float32)

    for note in notes:
        start_index = max(0, int(round(note.time * sample_rate)))
        end_index = min(sample_count, int(round((note.time + note.duration + tail_seconds) * sample_rate)))
        if end_index <= start_index:
            continue
        t = np.arange(end_index - start_index, dtype=np.float32) / sample_rate
        frequency = np.float32(440.0 * (2.0 ** ((note.note - 69) / 12.0)))
        attack = np.clip(t / 0.015, 0.0, 1.0)
        release_start = max(0.01, float(note.duration))
        release = np.where(t <= release_start, 1.0, np.exp(-(t - release_start) * 7.5))
        envelope = attack * release * np.exp(-t * 0.35)
        amplitude = (0.05 + 0.35 * (note.velocity / 127.0)) / max(1.0, math.sqrt(len(notes)))
        waveform = (
            np.sin(2.0 * np.pi * frequency * t)
            + 0.35 * np.sin(2.0 * np.pi * frequency * 2.0 * t)
            + 0.16 * np.sin(2.0 * np.pi * frequency * 3.0 * t)
        )
        audio[start_index:end_index] += (amplitude * envelope * waveform).astype(np.float32)

    peak = float(np.max(np.abs(audio))) if audio.size else 0.0
    if peak > 0:
        audio = audio / max(peak, 1.0) * 0.88
    pcm = np.clip(audio * 32767.0, -32768, 32767).astype(np.int16)

    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(pcm.tobytes())

    return duration


def synthesize_notes_to_wav(
    notes: list[NoteEvent],
    path: Path,
    *,
    minimum_duration: float = 0.8,
    tail_seconds: float = 0.35,
    sample_rate: int = SAMPLE_RATE,
) -> float:
    result = _synthesize_fluidsynth(
        notes, path,
        minimum_duration=minimum_duration,
        tail_seconds=tail_seconds,
        sample_rate=sample_rate,
    )
    if result is not None:
        return result
    return _synthesize_sine(
        notes, path,
        minimum_duration=minimum_duration,
        tail_seconds=tail_seconds,
        sample_rate=sample_rate,
    )


def extract_response_window(
    notes: list[NoteEvent],
    *,
    min_start_time: float,
    window_seconds: float,
    prompt_notes: list[NoteEvent] | None = None,
) -> tuple[list[NoteEvent], dict[str, Any]]:
    prompt_fingerprints = {
        (
            int(prompt_note.note),
            round(float(prompt_note.time), 2),
            round(float(prompt_note.duration), 2),
        )
        for prompt_note in (prompt_notes or [])
    }
    stripped_prompt_count = 0
    response_source: list[NoteEvent] = []
    for note in notes:
        fingerprint = (
            int(note.note),
            round(float(note.time), 2),
            round(float(note.duration), 2),
        )
        if fingerprint in prompt_fingerprints:
            stripped_prompt_count += 1
            continue
        response_source.append(note)

    candidates = sorted(
        [note for note in response_source if note.time >= min_start_time],
        key=lambda event: (event.time, event.note, event.duration),
    )
    window = max(0.01, float(window_seconds))
    debug: dict[str, Any] = {
        "source_note_count": len(notes),
        "discarded_matching_prompt_notes": stripped_prompt_count,
        "candidate_note_count": len(candidates),
        "min_start_time": round(float(min_start_time), 3),
        "window_seconds": round(window, 3),
    }
    if not candidates:
        return [], {
            **debug,
            "window_start_sec": None,
            "window_end_sec": None,
            "discarded_prompt_notes": len(response_source),
            "discarded_before_window": len(response_source),
            "discarded_after_window": 0,
            "emitted_notes": 0,
        }

    def overlap_duration(note: NoteEvent, window_start: float, window_end: float) -> float:
        return max(0.0, min(note.time + note.duration, window_end) - max(note.time, window_start))

    best_start = candidates[0].time
    best_score: tuple[int, float, float] = (-1, -1.0, -best_start)
    for candidate in candidates:
        window_start = candidate.time
        window_end = window_start + window
        overlapping = [
            note
            for note in candidates
            if note.time < window_end and note.time + note.duration > window_start
        ]
        score = (
            sum(1 for note in overlapping if window_start <= note.time < window_end),
            sum(overlap_duration(note, window_start, window_end) for note in overlapping),
            -window_start,
        )
        if score > best_score:
            best_score = score
            best_start = window_start

    best_end = best_start + window
    extracted: list[NoteEvent] = []
    for note in candidates:
        clipped_start = max(note.time, best_start)
        clipped_end = min(note.time + note.duration, best_end)
        if clipped_end <= clipped_start:
            continue
        extracted.append(
            NoteEvent(
                note=note.note,
                velocity=note.velocity,
                time=clipped_start - best_start,
                duration=max(0.01, clipped_end - clipped_start),
            )
        )

    extracted.sort(key=lambda event: (event.time, event.note, event.duration))
    return extracted, {
        **debug,
        "window_start_sec": round(best_start, 3),
        "window_end_sec": round(best_end, 3),
        "discarded_prompt_notes": len(response_source) - len(candidates),
        "discarded_before_window": sum(1 for note in candidates if note.time < best_start),
        "discarded_after_window": sum(1 for note in candidates if note.time >= best_end),
        "emitted_notes": len(extracted),
    }


def combine_prompt_and_reply(prompt: list[NoteEvent], reply: list[NoteEvent]) -> list[NoteEvent]:
    if not prompt:
        offset = 0.0
    else:
        offset = max(note.time + note.duration for note in prompt)
    combined = list(prompt)
    combined.extend(
        NoteEvent(
            note=note.note,
            velocity=note.velocity,
            time=offset + note.time,
            duration=note.duration,
        )
        for note in reply
    )
    return sorted(combined, key=lambda event: (event.time, event.note))


def note_dicts_to_events(note_dicts: list[dict[str, Any]]) -> list[NoteEvent]:
    return [
        NoteEvent(
            note=int(item["note"]),
            velocity=int(item.get("velocity", 80)),
            time=float(item["time"]),
            duration=float(item["duration"]),
        )
        for item in note_dicts
    ]
