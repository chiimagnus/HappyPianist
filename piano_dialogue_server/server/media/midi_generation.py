from __future__ import annotations

import random
import statistics
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, TYPE_CHECKING

import mido

if TYPE_CHECKING:
    from ..api.protocol import DialogueNote, GenerateParams

MAJOR_SCALE = {0, 2, 4, 5, 7, 9, 11}
MINOR_SCALE = {0, 2, 3, 5, 7, 8, 10}
ALL_PITCHES = list(range(21, 109))
NOTE_NAME_BY_CLASS = [
    "C",
    "C#",
    "D",
    "D#",
    "E",
    "F",
    "F#",
    "G",
    "G#",
    "A",
    "A#",
    "B",
]
KEY_SIGNATURE_BY_CLASS = {
    0: "C",
    1: "Gb",
    2: "D",
    3: "Eb",
    4: "E",
    5: "F",
    6: "F#",
    7: "G",
    8: "Ab",
    9: "A",
    10: "Bb",
    11: "B",
}


def _note_name(pitch_class: int) -> str:
    return NOTE_NAME_BY_CLASS[pitch_class % 12]


def _key_signature_name(root_class: int, mode: str) -> str:
    if mode == "minor":
        root_class = (root_class + 3) % 12
    return KEY_SIGNATURE_BY_CLASS[root_class]


@dataclass(frozen=True)
class NoteEvent:
    note: int
    velocity: int
    start: float
    duration: float
    channel: int
    track: int


@dataclass(frozen=True)
class MidiAnalysis:
    tempo_bpm: float
    time_signature: tuple[int, int]
    key_signature: str
    key_root: int
    key_mode: str
    pitch_range: tuple[int, int]
    average_velocity: float
    density_notes_per_second: float
    duration_seconds: float
    signature_count: int
    note_count: int
    motif: list[NoteEvent]


def _tempo_to_bpm(microseconds_per_beat: int) -> float:
    return 60_000_000 / microseconds_per_beat


def _best_key_signature(notes: list[NoteEvent]) -> tuple[str, int, str]:
    if not notes:
        return "C", 60, "major"

    histogram = {pitch % 12: 0 for pitch in range(12)}
    for note in notes:
        histogram[note.note % 12] += 1

    def score_root(root: int, scale: set[int]) -> int:
        return sum(histogram[(root + degree) % 12] for degree in scale)

    major_scores = [(score_root(root, MAJOR_SCALE), root) for root in range(12)]
    minor_scores = [(score_root(root, MINOR_SCALE), root) for root in range(12)]
    major_root = max(major_scores)[1]
    minor_root = max(minor_scores)[1]
    major_score = max(major_scores)[0]
    minor_score = max(minor_scores)[0]

    if major_score >= minor_score:
        key_name = _key_signature_name(major_root, "major")
        return (key_name, 60 + major_root, "major")
    key_name = _key_signature_name(minor_root, "minor")
    return (key_name, 60 + minor_root, "minor")


def _flatten_messages(mid: mido.MidiFile) -> list[tuple[int, mido.Message, int]]:
    events: list[tuple[int, mido.Message, int]] = []
    for track_index, track in enumerate(mid.tracks):
        absolute = 0
        for message in track:
            absolute += message.time
            events.append((absolute, message, track_index))
    return sorted(events, key=lambda item: item[0])


def parse_midi_file(path: Path) -> tuple[list[NoteEvent], MidiAnalysis]:
    mid = mido.MidiFile(path)
    tracks = list(mid.tracks)
    merged = _flatten_messages(mid)

    tempo = 500_000
    time_signature = (4, 4)
    key_signature = "C"
    key_root = 60
    key_mode = "major"

    active_notes: dict[tuple[int, int], tuple[int, int, int]] = {}
    note_events: list[NoteEvent] = []
    last_tick = 0
    current_time = 0.0

    for tick, message, track_index in merged:
        delta_ticks = tick - last_tick
        current_time += mido.tick2second(delta_ticks, mid.ticks_per_beat, tempo)
        last_tick = tick

        if message.type == "set_tempo":
            tempo = message.tempo
        elif message.type == "time_signature":
            time_signature = (message.numerator, message.denominator)
        elif message.type == "key_signature":
            key_signature = message.key
        elif message.type == "note_on" and message.velocity > 0:
            active_notes[(message.channel, message.note)] = (
                tick,
                message.note,
                message.velocity,
            )
        elif message.type == "note_off" or (message.type == "note_on" and message.velocity == 0):
            key = (message.channel, message.note)
            if key not in active_notes:
                continue
            start_tick, pitch, velocity = active_notes.pop(key)
            duration_ticks = tick - start_tick
            duration_seconds = max(0.01, mido.tick2second(duration_ticks, mid.ticks_per_beat, tempo))
            note_start_seconds = current_time - duration_seconds
            note_events.append(
                NoteEvent(
                    note=pitch,
                    velocity=velocity,
                    start=note_start_seconds,
                    duration=duration_seconds,
                    channel=message.channel,
                    track=track_index,
                )
            )

    note_events.sort(key=lambda n: n.start)
    metrics = _compute_analysis(note_events, key_signature, key_root, key_mode, tempo, time_signature)
    return note_events, metrics


def _compute_analysis(
    notes: list[NoteEvent],
    key_signature: str,
    key_root: int,
    key_mode: str,
    tempo: int,
    time_signature: tuple[int, int],
) -> MidiAnalysis:
    duration_seconds = 0.0
    if notes:
        duration_seconds = max(note.start + note.duration for note in notes)

    if notes:
        pitch_min = min(note.note for note in notes)
        pitch_max = max(note.note for note in notes)
        velocity_average = statistics.mean(note.velocity for note in notes)
    else:
        pitch_min, pitch_max = 60, 72
        velocity_average = 64.0

    density = len(notes) / max(1.0, duration_seconds)
    detected_key, detected_root, detected_mode = _best_key_signature(notes)

    return MidiAnalysis(
        tempo_bpm=_tempo_to_bpm(tempo),
        time_signature=time_signature,
        key_signature=detected_key,
        key_root=detected_root,
        key_mode=detected_mode,
        pitch_range=(pitch_min, pitch_max),
        average_velocity=velocity_average,
        density_notes_per_second=density,
        duration_seconds=duration_seconds,
        signature_count=len(notes),
        note_count=len(notes),
        motif=notes[-4:] if len(notes) >= 4 else notes,
    )


def analyze_dialogue_notes(notes: list["DialogueNote"]) -> MidiAnalysis:
    note_events = [
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
    return _compute_analysis(note_events, "C", 60, "major", 500_000, (4, 4))


def _scale_notes(root: int, mode: str) -> set[int]:
    root_pitch = root % 12
    if mode == "minor":
        return {(root_pitch + degree) % 12 for degree in MINOR_SCALE}
    return {(root_pitch + degree) % 12 for degree in MAJOR_SCALE}


def _closest_scale_note(pitch: int, scale: set[int], root: int) -> int:
    base = pitch % 12
    if base in scale:
        return pitch
    candidates = [pitch + offset for offset in (-2, -1, 1, 2, -3, 3)]
    valid = [candidate for candidate in candidates if candidate % 12 in scale and 21 <= candidate <= 108]
    return valid[0] if valid else pitch


def _build_chord(root_pitch: int, mode: str) -> list[int]:
    third = root_pitch + (4 if mode == "major" else 3)
    fifth = root_pitch + 7
    return [root_pitch, third, fifth]


def _extract_phrases(notes: list[NoteEvent], min_len: int = 6, max_len: int = 16) -> list[list[NoteEvent]]:
    """Extract multiple melodic phrases from the tail of the piece."""
    if len(notes) < min_len:
        return [notes] if notes else []

    phrases: list[list[NoteEvent]] = []
    # Last phrase of various lengths
    for length in (max_len, max_len - 4, max_len - 8):
        if length >= min_len and len(notes) >= length:
            phrases.append(notes[-length:])
    # Earlier phrases stepping back
    step = max_len // 2
    for start in range(max(0, len(notes) - max_len * 4), len(notes) - max_len, step):
        phrase = notes[start : start + max_len]
        if len(phrase) >= min_len:
            phrases.append(phrase)

    # Deduplicate by pitch sequence
    unique: list[list[NoteEvent]] = []
    seen: set[tuple[int, ...]] = set()
    for phrase in phrases:
        key = tuple(n.note for n in phrase)
        if key not in seen:
            seen.add(key)
            unique.append(phrase)

    return unique if unique else [notes[-min_len:]]


def _phrase_to_degrees(phrase: list[NoteEvent], key_root: int) -> list[int]:
    """Convert phrase pitches to scale degrees relative to key root."""
    return [n.note - key_root for n in phrase]


def _apply_inversion(degrees: list[int]) -> list[int]:
    """Mirror intervals: ascending becomes descending and vice versa."""
    if not degrees:
        return degrees
    result = [degrees[0]]
    for i in range(1, len(degrees)):
        interval = degrees[i] - degrees[i - 1]
        result.append(result[-1] - interval)
    return result


def _apply_sequence(degrees: list[int], shift: int) -> list[int]:
    """Transpose the entire phrase by shift semitones."""
    return [d + shift for d in degrees]


def _apply_rhythmic_variation(
    phrase: list[NoteEvent],
    density_factor: float = 1.0,
) -> list[tuple[float, float]]:
    """Return varied (duration, gap) pairs for a phrase."""
    result: list[tuple[float, float]] = []
    for i, note in enumerate(phrase):
        dur = note.duration
        if i + 1 < len(phrase):
            gap = phrase[i + 1].start - note.start
        else:
            gap = note.duration
        # Occasionally split long notes into shorter ones
        if gap > 0.6 and density_factor > 1.0:
            gap = gap / density_factor
            dur = dur / density_factor
        result.append((max(0.1, dur), max(0.1, gap)))
    return result


def _quantize_to_scale(pitch: int, scale: set[int], key_root: int) -> int:
    """Force pitch into the scale, preferring the closest octave."""
    pc = pitch % 12
    if pc in scale:
        return pitch
    # Search nearby
    for offset in (1, -1, 2, -2, 3, -3, 4, -4):
        candidate = pitch + offset
        if candidate % 12 in scale and 21 <= candidate <= 108:
            return candidate
    return max(21, min(108, _closest_scale_note(pitch, scale, key_root)))


def _clamp_pitch(pitch: int, pitch_range: tuple[int, int]) -> int:
    """Keep pitch within the original piece's range with some margin."""
    lo, hi = pitch_range
    margin = 3
    return max(lo - margin, min(hi + margin, pitch))


def _clamp_bass_pitch(pitch: int) -> int:
    while pitch > 48:
        pitch -= 12
    while pitch < 24:
        pitch += 12
    return max(24, min(48, pitch))


def _clamp_middle_voice(pitch: int, highest_allowed: int) -> int:
    while pitch > highest_allowed:
        pitch -= 12
    while pitch < 48:
        pitch += 12
    return max(48, min(highest_allowed, pitch))


def _is_diatonic(pitch: int, scale: set[int]) -> bool:
    return pitch % 12 in scale


def _choose_texture(analysis: MidiAnalysis, melody_slice: list[NoteEvent]) -> str:
    if not melody_slice:
        return "lyric"
    durations = [note.duration for note in melody_slice]
    avg_duration = statistics.mean(durations)
    short_ratio = sum(1 for duration in durations if duration <= 0.25) / len(durations)
    if short_ratio > 0.45 or analysis.density_notes_per_second > 4.0:
        return "grand"
    if avg_duration > 0.75 or len(melody_slice) <= 2:
        return "light"
    return "lyric"


def _weighted_voice_leading(
    candidates: list[tuple[int, int]],
    previous_inner: list[int] | None,
) -> tuple[int, int]:
    if previous_inner is None:
        return candidates[0]
    best = candidates[0]
    best_cost = float("inf")
    for inner1, inner2 in candidates:
        cost = abs(inner1 - previous_inner[0]) + abs(inner2 - previous_inner[1])
        if cost < best_cost:
            best_cost = cost
            best = (inner1, inner2)
    return best


def _generate_melody_continuation(
    source_notes: list[NoteEvent],
    analysis: MidiAnalysis,
    continuation_duration: float,
    seed: int | None = None,
) -> list[NoteEvent]:
    if not source_notes:
        tonic = analysis.key_root
        return [
            NoteEvent(note=tonic, velocity=80, start=0.0, duration=0.4, channel=0, track=0),
        ]

    rng = random.Random(seed)

    start_time = max(note.start + note.duration for note in source_notes)
    scale = _scale_notes(analysis.key_root, analysis.key_mode)
    base_velocity = 95
    pitch_lo, pitch_hi = analysis.pitch_range

    # Extract multiple phrases from the source
    phrases = _extract_phrases(source_notes)
    if not phrases:
        phrases = [source_notes[-4:]]

    # Convert phrases to degree sequences
    phrase_degrees = [_phrase_to_degrees(p, analysis.key_root) for p in phrases]

    # Target density controls maximum gap
    target_gap = min(0.8, max(0.15, 1.0 / max(analysis.density_notes_per_second, 0.5)))
    max_gap = max(1.0, target_gap * 2)

    # Variation strategies
    def vary_degrees(degrees: list[int], strategy: str) -> list[int]:
        if strategy == "inversion":
            return _apply_inversion(degrees)
        if strategy == "sequence_up":
            shift = 4 if analysis.key_mode == "major" else 3
            return _apply_sequence(degrees, shift)
        if strategy == "sequence_down":
            shift = -4 if analysis.key_mode == "major" else -3
            return _apply_sequence(degrees, shift)
        if strategy == "retrograde":
            return list(reversed(degrees))
        if strategy == "ornament":
            result: list[int] = []
            for i, d in enumerate(degrees):
                result.append(d)
                if i + 1 < len(degrees):
                    nxt = degrees[i + 1]
                    if abs(nxt - d) == 2:
                        result.append((d + nxt) // 2)
            return result
        if strategy == "fragment":
            # Take a random 4-7 note slice of the phrase
            frag_len = rng.randint(4, min(7, len(degrees)))
            start = rng.randint(0, len(degrees) - frag_len)
            return list(degrees[start : start + frag_len])
        return list(degrees)

    strategies = [
        "original",
        "inversion",
        "sequence_up",
        "retrograde",
        "ornament",
        "sequence_down",
        "fragment",
    ]

    continuation: list[NoteEvent] = []
    current_time = start_time

    while current_time < start_time + continuation_duration:
        # Randomly pick a phrase and a strategy
        phrase_i = rng.randint(0, len(phrase_degrees) - 1)
        strategy = rng.choice(strategies)

        degrees = phrase_degrees[phrase_i]
        varied_degrees = vary_degrees(degrees, strategy)
        rhythm = _apply_rhythmic_variation(phrases[phrase_i])

        for i, deg in enumerate(varied_degrees):
            if current_time >= start_time + continuation_duration:
                break

            pitch = analysis.key_root + deg
            pitch = _quantize_to_scale(pitch, scale, analysis.key_root)
            pitch = _clamp_pitch(pitch, (pitch_lo, pitch_hi))

            # Random velocity variation around base velocity
            vel = base_velocity + rng.randint(-8, 8)
            vel = max(1, min(127, vel))

            if i < len(rhythm):
                dur, gap = rhythm[i]
            else:
                dur, gap = 0.3, 0.4

            # Random rhythmic micro-variation
            gap *= rng.uniform(0.85, 1.15)
            dur *= rng.uniform(0.9, 1.1)

            effective_gap = min(gap, max_gap)
            effective_gap = max(0.08, effective_gap)
            effective_dur = min(max(dur, 0.1), effective_gap * 0.92)

            continuation.append(
                NoteEvent(
                    note=pitch,
                    velocity=vel,
                    start=current_time,
                    duration=effective_dur,
                    channel=0,
                    track=0,
                )
            )
            current_time += effective_gap

    return continuation


def _generate_melody_continuation_with_model(
    source_notes: list[NoteEvent],
    analysis: MidiAnalysis,
    continuation_duration: float,
) -> list[NoteEvent]:
    """Generate continuation using the AMT model."""
    try:
        # Import locally to avoid circular dependency
        import sys
        from pathlib import Path as PathlibPath
        
        # Ensure inference module can be imported
        server_dir = PathlibPath(__file__).parent
        if str(server_dir) not in sys.path:
            sys.path.insert(0, str(server_dir))
        
        from inference import get_inference_engine
        from protocol import GenerateParams, DialogueNote
    except ImportError as e:
        raise RuntimeError(f"Inference engine not available: {e}")

    if not source_notes:
        return []

    try:
        engine = get_inference_engine()
    except Exception as e:
        raise RuntimeError(f"Failed to initialize inference engine: {e}")
    
    prompt_notes = [
        DialogueNote(
            note=int(n.note),
            velocity=int(n.velocity),
            time=float(n.start),
            duration=float(n.duration),
        )
        for n in source_notes
    ]
    
    params = GenerateParams(
        top_p=0.95,
        max_tokens=256,
        strategy="model",
    )
    
    response_notes = engine.generate_response(prompt_notes, params, session_id=None)
    
    continuation: list[NoteEvent] = [
        NoteEvent(
            note=int(n.note),
            velocity=int(n.velocity),
            start=float(n.time),
            duration=float(n.duration),
            channel=0,
            track=0,
        )
        for n in response_notes
    ]
    
    return continuation


def _generate_accompaniment(
    source_notes: list[NoteEvent],
    analysis: MidiAnalysis,
    bar_length: float,
) -> list[NoteEvent]:
    if not source_notes:
        return []

    max_end = max(note.start + note.duration for note in source_notes)
    min_start = min(note.start for note in source_notes)
    root_scale = _scale_notes(analysis.key_root, analysis.key_mode)
    accompaniment: list[NoteEvent] = []

    first_bar = int(min_start // bar_length)
    last_bar = int(max_end // bar_length) + 1
    previous_inner: list[int] | None = None
    previous_bass: int | None = None

    for current_bar in range(first_bar, last_bar):
        bar_start = current_bar * bar_length
        melody_slice = [note for note in source_notes if bar_start <= note.start < bar_start + bar_length]
        if melody_slice:
            chord_root = _closest_scale_note(melody_slice[0].note, root_scale, analysis.key_root)
        else:
            chord_root = analysis.key_root

        melody_min = min((note.note for note in melody_slice), default=64)
        middle_max = min(59, max(48, melody_min - 4))
        texture = _choose_texture(analysis, melody_slice)

        bass_root = _closest_scale_note(chord_root, root_scale, analysis.key_root)
        bass_candidate = _clamp_bass_pitch(bass_root)
        fifth_candidate = _clamp_bass_pitch(bass_root + 7)
        bass = bass_candidate
        if previous_bass is not None and abs(fifth_candidate - previous_bass) < abs(bass_candidate - previous_bass):
            bass = fifth_candidate
        previous_bass = bass

        chord_third = bass_root + (4 if analysis.key_mode == "major" else 3)
        chord_fifth = bass_root + 7
        potential_inner = []
        for pitch in (chord_third, chord_fifth, bass_root + 12, chord_third + 12):
            clamped = _clamp_middle_voice(pitch, middle_max)
            if clamped not in potential_inner:
                potential_inner.append(clamped)

        if len(potential_inner) < 2:
            potential_inner = [_clamp_middle_voice(chord_third, middle_max), _clamp_middle_voice(chord_fifth, middle_max)]

        inner_options: list[tuple[int, int]] = []
        for i in range(len(potential_inner)):
            for j in range(i + 1, len(potential_inner)):
                if abs(potential_inner[i] - potential_inner[j]) >= 3:
                    inner_options.append((potential_inner[i], potential_inner[j]))
        if not inner_options:
            inner_options = [(potential_inner[0], potential_inner[-1])]

        inner1, inner2 = _weighted_voice_leading(inner_options, previous_inner)
        previous_inner = [inner1, inner2]

        def velocity_for_beat(is_downbeat: bool) -> int:
            if is_downbeat:
                return max(1, min(127, 90 + random.randint(-5, 5)))
            return max(1, min(127, 65 + random.randint(-10, 10)))

        if texture == "grand":
            accompaniment.append(
                NoteEvent(note=bass, velocity=velocity_for_beat(True), start=bar_start, duration=bar_length * 0.95, channel=1, track=1)
            )
            accompaniment.append(
                NoteEvent(note=inner1, velocity=velocity_for_beat(False), start=bar_start, duration=bar_length * 0.9, channel=1, track=1)
            )
            accompaniment.append(
                NoteEvent(note=inner2, velocity=velocity_for_beat(False), start=bar_start + bar_length * 0.5, duration=bar_length * 0.45, channel=1, track=1)
            )
        elif texture == "light":
            accompaniment.append(
                NoteEvent(note=bass, velocity=velocity_for_beat(True), start=bar_start, duration=bar_length * 0.95, channel=1, track=1)
            )
            for offset in (bar_length * 0.28, bar_length * 0.56, bar_length * 0.82):
                accompaniment.append(
                    NoteEvent(
                        note=inner1 if offset != bar_length * 0.82 else inner2,
                        velocity=velocity_for_beat(False),
                        start=bar_start + offset,
                        duration=bar_length * 0.2,
                        channel=1,
                        track=1,
                    )
                )
        else:
            accompaniment.append(
                NoteEvent(note=bass, velocity=velocity_for_beat(True), start=bar_start, duration=bar_length * 0.95, channel=1, track=1)
            )
            accompaniment.append(
                NoteEvent(note=inner1, velocity=velocity_for_beat(False), start=bar_start + 0.0, duration=bar_length * 0.45, channel=1, track=1)
            )
            accompaniment.append(
                NoteEvent(note=inner2, velocity=velocity_for_beat(False), start=bar_start + bar_length * 0.5, duration=bar_length * 0.35, channel=1, track=1)
            )
            accompaniment.append(
                NoteEvent(note=inner1, velocity=velocity_for_beat(False), start=bar_start + bar_length * 0.8, duration=bar_length * 0.18, channel=1, track=1)
            )

    accompaniment.sort(key=lambda n: n.start)
    return accompaniment


def generate_expanded_midi(
    source_notes: list[NoteEvent],
    analysis: MidiAnalysis,
    mode: str = "variation",
    extra_duration: float | None = None,
    include_source: bool = True,
    seed: int | None = None,
    use_model: bool = False,
) -> tuple[list[NoteEvent], list[NoteEvent]]:
    if extra_duration is None:
        extra_duration = max(4.0, analysis.duration_seconds * 0.5)

    if mode in {"continue", "variation", "emotion"}:
        if use_model:
            continuation = _generate_melody_continuation_with_model(source_notes, analysis, extra_duration)
        else:
            continuation = _generate_melody_continuation(source_notes, analysis, extra_duration, seed=seed)
        if include_source:
            melody = source_notes.copy()
            melody.extend(continuation)
        else:
            melody = list(continuation)
    elif mode == "accompaniment":
        continuation = []
        melody = source_notes.copy() if include_source else []
    else:
        if use_model:
            continuation = _generate_melody_continuation_with_model(source_notes, analysis, extra_duration)
        else:
            continuation = _generate_melody_continuation(source_notes, analysis, extra_duration, seed=seed)
        if include_source:
            melody = source_notes.copy()
            melody.extend(continuation)
        else:
            melody = list(continuation)

    accompaniment_source = source_notes + continuation if include_source else continuation
    accompaniment = _generate_accompaniment(accompaniment_source, analysis, bar_length=4.0)
    return melody, accompaniment


def write_continuation_midi(
    continuation: Iterable[NoteEvent],
    accompaniment: Iterable[NoteEvent],
    analysis: MidiAnalysis,
    output_path: Path,
) -> None:
    """Write only generated continuation notes to a new MIDI file, with time offset to start at 0."""
    cont_list = list(continuation)
    acc_list = list(accompaniment)
    all_notes = cont_list + acc_list
    if not all_notes:
        min_start = 0.0
    else:
        min_start = min(note.start for note in all_notes)

    def _offset(events: list[NoteEvent]) -> list[NoteEvent]:
        return [
            NoteEvent(
                note=n.note,
                velocity=n.velocity,
                start=max(0.0, n.start - min_start),
                duration=n.duration,
                channel=n.channel,
                track=n.track,
            )
            for n in events
        ]

    write_midi(_offset(cont_list), _offset(acc_list), analysis, output_path)


def write_midi(
    melody: Iterable[NoteEvent],
    accompaniment: Iterable[NoteEvent],
    analysis: MidiAnalysis,
    output_path: Path,
) -> None:
    midi = mido.MidiFile(ticks_per_beat=480)
    track_meta = mido.MidiTrack()
    midi.tracks.append(track_meta)

    tempo = mido.bpm2tempo(int(round(analysis.tempo_bpm)))
    track_meta.append(mido.MetaMessage("set_tempo", tempo=tempo, time=0))
    track_meta.append(
        mido.MetaMessage(
            "time_signature",
            numerator=analysis.time_signature[0],
            denominator=analysis.time_signature[1],
            time=0,
        )
    )
    track_meta.append(mido.MetaMessage("key_signature", key=analysis.key_signature, time=0))

    def append_notes(track: mido.MidiTrack, events: Iterable[NoteEvent]) -> None:
        pending: list[tuple[float, mido.Message]] = []
        for note in events:
            note_on = mido.Message("note_on", note=note.note, velocity=note.velocity, time=0, channel=note.channel)
            note_off = mido.Message("note_off", note=note.note, velocity=0, time=0, channel=note.channel)
            pending.append((note.start, note_on))
            pending.append((note.start + note.duration, note_off))

        pending.sort(key=lambda item: item[0])
        last_time = 0.0
        for event_time, msg in pending:
            delta = max(0.0, event_time - last_time)
            msg.time = int(round(mido.second2tick(delta, midi.ticks_per_beat, tempo)))
            track.append(msg)
            last_time = event_time

    track_melody = mido.MidiTrack()
    track_accompaniment = mido.MidiTrack()
    midi.tracks.append(track_melody)
    midi.tracks.append(track_accompaniment)
    append_notes(track_melody, [note for note in melody if note.channel == 0])
    append_notes(track_accompaniment, [note for note in accompaniment if note.channel == 1])

    # Ensure each track ends with end_of_track for player compatibility
    for track in midi.tracks:
        if not track or track[-1].type != "end_of_track":
            track.append(mido.MetaMessage("end_of_track", time=0))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    midi.save(str(output_path))


def summarize_analysis(analysis: MidiAnalysis) -> dict[str, object]:
    return {
        "tempo_bpm": analysis.tempo_bpm,
        "time_signature": analysis.time_signature,
        "key_signature": analysis.key_signature,
        "key_mode": analysis.key_mode,
        "pitch_range": analysis.pitch_range,
        "average_velocity": analysis.average_velocity,
        "density_notes_per_second": analysis.density_notes_per_second,
        "duration_seconds": analysis.duration_seconds,
        "note_count": analysis.note_count,
        "motif_length": len(analysis.motif),
    }
