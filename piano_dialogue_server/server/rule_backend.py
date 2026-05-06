from __future__ import annotations

import math
import random
import time
from dataclasses import dataclass, field
from typing import Any

from .midi_utils import NoteEvent


# ---------------------------------------------------------------------------
# Scale / chord constants
# ---------------------------------------------------------------------------

MAJOR_SCALE = (0, 2, 4, 5, 7, 9, 11)
NATURAL_MINOR_SCALE = (0, 2, 3, 5, 7, 8, 10)
MAJOR_PENTATONIC = (0, 2, 4, 7, 9)
MINOR_PENTATONIC = (0, 3, 5, 7, 10)
BLUES_SCALE = (0, 3, 5, 6, 7, 10)
MIXOLYDIAN = (0, 2, 4, 5, 7, 9, 10)
DORIAN = (0, 2, 3, 5, 7, 9, 10)
LYDIAN = (0, 2, 4, 6, 7, 9, 11)
PHRYGIAN = (0, 1, 3, 5, 7, 8, 10)
HARMONIC_MINOR = (0, 2, 3, 5, 7, 8, 11)

CHORD_QUALITY_INTERVALS: dict[str, tuple[int, ...]] = {
    "major": (0, 4, 7),
    "minor": (0, 3, 7),
    "dominant7": (0, 4, 7, 10),
    "major7": (0, 4, 7, 11),
    "minor7": (0, 3, 7, 10),
    "sus4": (0, 5, 7),
    "sus2": (0, 2, 7),
    "diminished": (0, 3, 6),
    "augmented": (0, 4, 8),
}

# For scoring: some qualities are "extensions" of simpler ones
_QUALITY_BASE: dict[str, str] = {
    "dominant7": "major",
    "major7": "major",
    "minor7": "minor",
}


# ---------------------------------------------------------------------------
# Functional harmony transition table
# Scale degrees (0-based semitone offset from tonal root) mapped to
# Roman numeral function. Transitions express which degrees commonly follow.
# Weights are relative preferences (higher = more likely).
# ---------------------------------------------------------------------------

# Major key: degree → list of (next_degree, weight)
_MAJOR_TRANSITIONS: dict[int, list[tuple[int, float]]] = {
    0: [(5, 3.0), (7, 3.0), (9, 2.0), (2, 1.5), (4, 1.0)],   # I → IV, V, vi, ii, iii
    2: [(7, 3.0), (5, 1.5), (0, 1.0)],                          # ii → V, IV, I
    4: [(9, 2.5), (5, 2.0), (0, 1.0)],                          # iii → vi, IV, I
    5: [(7, 3.0), (0, 2.5), (2, 2.0), (9, 1.0)],               # IV → V, I, ii, vi
    7: [(0, 4.0), (9, 2.0), (5, 1.0)],                          # V → I, vi (deceptive), IV
    9: [(5, 3.0), (2, 2.5), (7, 2.0), (4, 1.0)],               # vi → IV, ii, V, iii
    11: [(0, 3.0), (4, 1.5)],                                    # vii° → I, iii
}

# Minor key: degree → list of (next_degree, weight)
_MINOR_TRANSITIONS: dict[int, list[tuple[int, float]]] = {
    0: [(5, 3.0), (7, 3.0), (8, 2.0), (3, 2.0), (10, 1.5)],   # i → iv, v/V, VI, III, VII
    2: [(7, 3.0), (5, 1.5)],                                     # ii° → v, iv
    3: [(8, 2.5), (5, 2.0), (0, 1.5)],                          # III → VI, iv, i
    5: [(7, 3.0), (0, 2.5), (8, 1.5)],                          # iv → v/V, i, VI
    7: [(0, 4.0), (8, 2.0), (5, 1.0)],                          # v/V → i, VI, iv
    8: [(5, 3.0), (3, 2.0), (2, 1.5)],                          # VI → iv, III, ii°
    10: [(3, 3.0), (0, 2.5), (5, 1.5)],                         # VII → III, i, iv
}


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class TonalCenter:
    root_pc: int
    mode: str


@dataclass(frozen=True)
class ChordGuess:
    root_pc: int
    quality: str
    score: float
    pitch_classes: tuple[int, ...]


@dataclass(frozen=True)
class MeasureChord:
    """Chord assigned to a specific measure index."""
    measure_index: int
    chord: ChordGuess


@dataclass(frozen=True)
class ChordProgression:
    """A sequence of chords, one per measure."""
    chords: list[MeasureChord]
    tonal: TonalCenter
    is_looping: bool = False
    loop_length: int = 0


@dataclass(frozen=True)
class RuleResult:
    notes: list[NoteEvent]
    timings: dict[str, int]
    debug: dict[str, Any]


# ---------------------------------------------------------------------------
# Style rules
# ---------------------------------------------------------------------------

STYLE_RULES: dict[str, dict[str, Any]] = {
    "pop": {
        "label": "Pop",
        "scale": "major_pentatonic",
        "density": 1.0,
        "duration": "clean",
        "timing": "straight",
        "velocity": (70, 98),
        "strong_degrees": (0, 4, 7),
    },
    "worship": {
        "label": "Worship",
        "scale": "major_add9",
        "density": 0.75,
        "duration": "legato",
        "timing": "straight",
        "velocity": (62, 92),
        "strong_degrees": (0, 2, 7),
    },
    "rock": {
        "label": "Rock",
        "scale": "minor_blues",
        "density": 1.0,
        "duration": "short",
        "timing": "straight",
        "velocity": (88, 115),
        "strong_degrees": (0, 7, 10),
    },
    "blues": {
        "label": "Blues",
        "scale": "blues",
        "density": 0.85,
        "duration": "breathy",
        "timing": "swing",
        "velocity": (72, 108),
        "strong_degrees": (0, 3, 7, 10),
    },
    "funk": {
        "label": "Funk",
        "scale": "minor_pentatonic",
        "density": 0.85,
        "duration": "staccato",
        "timing": "tight_16th",
        "velocity": (45, 110),
        "strong_degrees": (0, 3, 7),
    },
    "rnb": {
        "label": "R&B",
        "scale": "dorian",
        "density": 0.75,
        "duration": "short",
        "timing": "behind",
        "velocity": (58, 92),
        "strong_degrees": (4, 10, 2),
    },
    "neo_soul": {
        "label": "Neo Soul",
        "scale": "dorian_color",
        "density": 0.65,
        "duration": "breathy",
        "timing": "behind",
        "velocity": (52, 88),
        "strong_degrees": (4, 10, 2, 5),
    },
    "country": {
        "label": "Country",
        "scale": "major_pentatonic",
        "density": 1.0,
        "duration": "clean",
        "timing": "straight",
        "velocity": (78, 104),
        "strong_degrees": (0, 4, 7, 9),
    },
}


# ---------------------------------------------------------------------------
# Pitch-class / scale helpers
# ---------------------------------------------------------------------------

def _pitch_class_set(root_pc: int, intervals: tuple[int, ...]) -> list[int]:
    return sorted({(root_pc + interval) % 12 for interval in intervals})


def _chord_pitch_classes(root_pc: int, quality: str) -> tuple[int, ...]:
    intervals = CHORD_QUALITY_INTERVALS.get(quality, CHORD_QUALITY_INTERVALS["major"])
    return tuple(_pitch_class_set(root_pc, intervals))


def _scale_for_chord(chord: ChordGuess, tonal: TonalCenter, style: str) -> list[int]:
    """Select a scale that is compatible with the given chord.

    The scale is chosen based on chord quality and its relationship to the
    tonal center, then intersected with style preferences where possible.
    """
    root = chord.root_pc
    quality = chord.quality
    # Determine interval from tonal root to chord root
    interval = (root - tonal.root_pc) % 12

    if tonal.mode == "major":
        # Common chord functions in major key
        if quality in ("major", "major7", "dominant7"):
            if interval == 0:
                # I: use major scale (or pentatonic for style)
                return _pitch_class_set(root, MAJOR_SCALE)
            elif interval == 5:
                # IV: lydian flavor
                return _pitch_class_set(root, LYDIAN)
            elif interval == 7:
                # V: mixolydian
                return _pitch_class_set(root, MIXOLYDIAN)
            else:
                return _pitch_class_set(root, MIXOLYDIAN)
        elif quality in ("minor", "minor7"):
            if interval == 2:
                # ii: dorian
                return _pitch_class_set(root, DORIAN)
            elif interval == 4:
                # iii: phrygian
                return _pitch_class_set(root, PHRYGIAN)
            elif interval == 9:
                # vi: natural minor / aeolian
                return _pitch_class_set(root, NATURAL_MINOR_SCALE)
            else:
                return _pitch_class_set(root, DORIAN)
        elif quality == "diminished":
            return _pitch_class_set(root, (0, 2, 3, 5, 6, 8, 9, 11))  # diminished scale
        elif quality == "sus4":
            return _pitch_class_set(root, MIXOLYDIAN)
        elif quality == "sus2":
            return _pitch_class_set(root, MAJOR_SCALE)
        else:
            return _pitch_class_set(root, MAJOR_SCALE)
    else:
        # Minor key
        if quality in ("minor", "minor7"):
            if interval == 0:
                # i: natural minor or dorian depending on style
                if style in ("funk", "rnb", "neo_soul"):
                    return _pitch_class_set(root, DORIAN)
                return _pitch_class_set(root, NATURAL_MINOR_SCALE)
            elif interval == 5:
                # iv: dorian from iv's perspective
                return _pitch_class_set(root, DORIAN)
            else:
                return _pitch_class_set(root, DORIAN)
        elif quality in ("major", "major7", "dominant7"):
            if interval == 3:
                # III: major scale
                return _pitch_class_set(root, MAJOR_SCALE)
            elif interval == 8:
                # VI: major scale / lydian
                return _pitch_class_set(root, LYDIAN)
            elif interval == 7:
                # V (dominant in minor): mixolydian or harmonic minor from i
                return _pitch_class_set(tonal.root_pc, HARMONIC_MINOR)
            elif interval == 10:
                # VII: mixolydian
                return _pitch_class_set(root, MIXOLYDIAN)
            else:
                return _pitch_class_set(root, MIXOLYDIAN)
        elif quality == "diminished":
            return _pitch_class_set(root, (0, 2, 3, 5, 6, 8, 9, 11))
        elif quality in ("sus4", "sus2"):
            return _pitch_class_set(root, NATURAL_MINOR_SCALE)
        else:
            return _pitch_class_set(root, NATURAL_MINOR_SCALE)


def _style_scale(root_pc: int, mode: str, style: str) -> list[int]:
    """Legacy style-based scale selection (used as fallback)."""
    rule = STYLE_RULES.get(style, STYLE_RULES["pop"])
    scale_name = rule["scale"]
    if scale_name == "major_pentatonic":
        return _pitch_class_set(root_pc, MAJOR_PENTATONIC if mode == "major" else MINOR_PENTATONIC)
    if scale_name == "major_add9":
        return _pitch_class_set(root_pc, tuple(sorted(set(MAJOR_PENTATONIC + (2,)))))
    if scale_name == "minor_blues":
        return _pitch_class_set(root_pc, BLUES_SCALE)
    if scale_name == "blues":
        return _pitch_class_set(root_pc, BLUES_SCALE)
    if scale_name == "minor_pentatonic":
        return _pitch_class_set(root_pc, MINOR_PENTATONIC)
    if scale_name == "dorian":
        return _pitch_class_set(root_pc, DORIAN)
    if scale_name == "dorian_color":
        return _pitch_class_set(root_pc, tuple(sorted(set(DORIAN + (5,)))))
    return _pitch_class_set(root_pc, MAJOR_PENTATONIC)


def _style_filtered_scale(full_scale: list[int], style: str) -> list[int]:
    """Optionally reduce a full 7-note scale to a pentatonic subset for style.

    Some styles (pop, country, worship) sound better with fewer passing tones.
    """
    rule = STYLE_RULES.get(style, STYLE_RULES["pop"])
    scale_name = rule["scale"]
    # If style expects pentatonic-level density, thin out the scale
    if scale_name in ("major_pentatonic", "minor_pentatonic", "major_add9") and len(full_scale) > 6:
        # Keep only notes that are in the pentatonic subset of the same root
        # Find scale root (first element)
        root = full_scale[0] if full_scale else 0
        if any(((pc - root) % 12) == 3 for pc in full_scale):
            # Minor-ish: use minor pentatonic filter
            penta = set(_pitch_class_set(root, MINOR_PENTATONIC))
        else:
            penta = set(_pitch_class_set(root, MAJOR_PENTATONIC))
        filtered = [pc for pc in full_scale if pc in penta]
        return filtered if len(filtered) >= 4 else full_scale
    return full_scale


# ---------------------------------------------------------------------------
# Tonal analysis
# ---------------------------------------------------------------------------

def infer_tonal_center(notes: list[NoteEvent]) -> TonalCenter:
    if not notes:
        return TonalCenter(root_pc=0, mode="major")

    weights = [0.0] * 12
    phrase_end = max(note.time + note.duration for note in notes)
    for note in notes:
        recency = 1.0 + max(0.0, note.time + note.duration - phrase_end + 4.0) / 4.0
        duration_weight = max(0.1, min(2.0, note.duration))
        weights[note.note % 12] += duration_weight * recency

    best_root = 0
    best_mode = "major"
    best_score = -1.0
    for root in range(12):
        for mode, intervals in (("major", MAJOR_SCALE), ("minor", NATURAL_MINOR_SCALE)):
            scale = {(root + interval) % 12 for interval in intervals}
            triad = {(root + interval) % 12 for interval in ((0, 4, 7) if mode == "major" else (0, 3, 7))}
            score = sum(weights[pc] * (1.5 if pc in triad else 1.0) for pc in scale)
            score += weights[root] * 0.75
            if score > best_score:
                best_root = root
                best_mode = mode
                best_score = score

    return TonalCenter(root_pc=best_root, mode=best_mode)


# ---------------------------------------------------------------------------
# Chord inference (single window)
# ---------------------------------------------------------------------------

def infer_chord_from_notes(
    notes: list[NoteEvent],
    tonal: TonalCenter | None = None,
    *,
    context_seconds: float = 4.0,
) -> ChordGuess:
    if tonal is None:
        tonal = infer_tonal_center(notes)
    if not notes:
        quality = "minor" if tonal.mode == "minor" else "major"
        return ChordGuess(
            root_pc=tonal.root_pc,
            quality=quality,
            score=0.0,
            pitch_classes=_chord_pitch_classes(tonal.root_pc, quality),
        )

    phrase_end = max(note.time + note.duration for note in notes)
    start = max(0.0, phrase_end - max(0.25, context_seconds))
    recent = [note for note in notes if note.time + note.duration > start]
    if not recent:
        recent = notes

    weights = [0.0] * 12
    for note in recent:
        duration_weight = max(0.12, min(1.5, note.duration))
        recency = 1.0 + max(0.0, note.time + note.duration - phrase_end + context_seconds) / max(0.25, context_seconds)
        weights[note.note % 12] += duration_weight * recency

    total_weight = sum(weights) or 1.0
    best = ChordGuess(
        root_pc=tonal.root_pc,
        quality="minor" if tonal.mode == "minor" else "major",
        score=-1.0,
        pitch_classes=_chord_pitch_classes(tonal.root_pc, "minor" if tonal.mode == "minor" else "major"),
    )
    for root in range(12):
        for quality, intervals in CHORD_QUALITY_INTERVALS.items():
            pitch_classes = _chord_pitch_classes(root, quality)
            chord_set = set(pitch_classes)
            matched = sum(weights[pc] for pc in chord_set)
            root_weight = weights[root]
            third_weight = weights[(root + intervals[1]) % 12]
            fifth_weight = weights[(root + intervals[2]) % 12] if len(intervals) > 2 else 0.0

            score = matched * 2.0 + root_weight * 0.5 + min(third_weight, fifth_weight) * 0.25
            score -= (total_weight - matched) * 0.2

            # Penalize chords whose root is not present in the notes
            if root_weight < 0.1:
                score -= 0.6

            # Prefer simpler chord qualities unless the extra note is clearly present
            if quality in _QUALITY_BASE:
                # 7th chords get a penalty unless the 7th is clearly heard
                # AND the base triad is also well-supported
                seventh_pc = (root + intervals[-1]) % 12
                seventh_weight = weights[seventh_pc]
                if seventh_weight < 0.3:
                    score -= 0.5  # penalize if 7th is barely present
                elif root_weight < 0.1:
                    score -= 0.3  # 7th present but root missing: unlikely
                else:
                    score += seventh_weight * 0.2  # bonus if 7th AND root are clear

            if quality in ("sus4", "sus2"):
                # sus chords need the sus note present and 3rd absent
                third_major = (root + 4) % 12
                third_minor = (root + 3) % 12
                if weights[third_major] > 0.3 or weights[third_minor] > 0.3:
                    score -= 0.8  # 3rd is present, probably not sus

            if quality in ("diminished", "augmented"):
                score -= 0.3  # slight penalty for rare qualities

            if tonal and root == tonal.root_pc:
                score += 0.15
            if tonal and ((tonal.mode == "major" and quality == "major") or (tonal.mode == "minor" and quality == "minor")):
                score += 0.05
            if score > best.score:
                best = ChordGuess(root_pc=root, quality=quality, score=score, pitch_classes=pitch_classes)

    return best


# ---------------------------------------------------------------------------
# Per-measure chord inference
# ---------------------------------------------------------------------------

def infer_chords_per_measure(
    notes: list[NoteEvent],
    tonal: TonalCenter,
    *,
    seconds_per_measure: float,
    total_measures: int,
) -> list[ChordGuess]:
    """Infer one chord per measure from the input notes.

    Returns a list of length total_measures.
    """
    if not notes or seconds_per_measure <= 0 or total_measures <= 0:
        quality = "minor" if tonal.mode == "minor" else "major"
        default = ChordGuess(
            root_pc=tonal.root_pc,
            quality=quality,
            score=0.0,
            pitch_classes=_chord_pitch_classes(tonal.root_pc, quality),
        )
        return [default] * max(1, total_measures)

    chords: list[ChordGuess] = []
    for measure_idx in range(total_measures):
        measure_start = measure_idx * seconds_per_measure
        measure_end = (measure_idx + 1) * seconds_per_measure

        # Get notes that overlap this measure
        measure_notes = [
            NoteEvent(
                note=n.note,
                velocity=n.velocity,
                time=max(0.0, n.time - measure_start),
                duration=min(n.duration, measure_end - max(n.time, measure_start)),
            )
            for n in notes
            if n.time < measure_end and n.time + n.duration > measure_start
        ]

        if measure_notes:
            chord = infer_chord_from_notes(
                measure_notes, tonal, context_seconds=seconds_per_measure
            )
        else:
            # No notes in this measure - carry forward from previous or use tonic
            if chords:
                chord = chords[-1]
            else:
                quality = "minor" if tonal.mode == "minor" else "major"
                chord = ChordGuess(
                    root_pc=tonal.root_pc,
                    quality=quality,
                    score=0.0,
                    pitch_classes=_chord_pitch_classes(tonal.root_pc, quality),
                )
        chords.append(chord)

    return chords


# ---------------------------------------------------------------------------
# Chord progression prediction
# ---------------------------------------------------------------------------

def _chord_to_degree(chord: ChordGuess, tonal: TonalCenter) -> int:
    """Map chord root to scale degree (semitone offset from tonal root)."""
    return (chord.root_pc - tonal.root_pc) % 12


def _degree_to_chord_quality(degree: int, mode: str) -> str:
    """Default chord quality for a scale degree in a given mode."""
    if mode == "major":
        major_degrees = {0, 5, 7}  # I, IV, V
        minor_degrees = {2, 4, 9}  # ii, iii, vi
        dim_degrees = {11}          # vii°
        if degree in major_degrees:
            return "major"
        elif degree in minor_degrees:
            return "minor"
        elif degree in dim_degrees:
            return "diminished"
        # For non-diatonic degrees, guess based on interval
        return "major"
    else:
        minor_degrees = {0, 5, 7}   # i, iv, v
        major_degrees = {3, 8, 10}  # III, VI, VII
        dim_degrees = {2}            # ii°
        if degree in minor_degrees:
            return "minor"
        elif degree in major_degrees:
            return "major"
        elif degree in dim_degrees:
            return "diminished"
        return "minor"


def _chords_match(a: ChordGuess, b: ChordGuess) -> bool:
    """Check if two chords are 'the same' for loop detection purposes.

    Matches by root only — quality variants (e.g., Bm vs Bm7) are treated
    as the same chord since pop/rock progressions reharmonize freely.
    """
    return a.root_pc == b.root_pc


def _detect_loop(chords: list[ChordGuess]) -> tuple[bool, int]:
    """Detect if the chord sequence has a repeating loop pattern.

    Strategies:
    1. Exact full-sequence loop (root-only matching, tolerates quality diffs)
    2. Subsequence loop: find the longest repeating pattern within the sequence,
       allowing a prefix/suffix that doesn't match (e.g., pickup measures)

    Returns (is_looping, loop_length).
    """
    if len(chords) < 2:
        return False, 0

    # Strategy 1: Full-sequence loop with root-only matching
    for loop_len in range(1, len(chords) // 2 + 1):
        pattern = chords[:loop_len]
        is_loop = True
        for i in range(loop_len, len(chords)):
            if not _chords_match(chords[i], pattern[i % loop_len]):
                is_loop = False
                break
        if is_loop:
            return True, loop_len

    # Strategy 2: Subsequence loop detection
    # Try to find a repeating pattern of length 2..N-2 that appears at least
    # partially repeated in the sequence (possibly with offset). This handles
    # cases like [Am, Bm, G, D, A, Bm] where the loop is [Bm, G, D, A]
    # starting at index 1 (the Am is a pickup/intro chord).
    best_loop_len = 0
    best_loop_start = 0
    best_coverage = 0

    max_loop_len = len(chords) - 1  # A loop of N-1 in N chords can still show partial repeat
    for loop_len in range(2, max_loop_len + 1):
        # Try each possible starting offset
        for start in range(len(chords) - loop_len):
            pattern = chords[start:start + loop_len]
            # Count how many consecutive measures from 'start' match the pattern
            match_count = 0
            for i in range(start, len(chords)):
                if _chords_match(chords[i], pattern[(i - start) % loop_len]):
                    match_count += 1
                else:
                    break
            # Need more than one full cycle (at least loop_len + 1 matches)
            coverage = match_count
            if match_count > loop_len and coverage > best_coverage:
                best_coverage = coverage
                best_loop_len = loop_len
                best_loop_start = start

    # Accept if the loop covers at least 60% of the sequence
    if best_loop_len >= 2 and best_coverage >= len(chords) * 0.6:
        return True, best_loop_len

    return False, 0


def _find_loop_pattern(chords: list[ChordGuess], loop_length: int) -> list[ChordGuess]:
    """Extract the canonical loop pattern from a chord sequence.

    Finds the best starting offset where the pattern of length `loop_length`
    has the most consecutive matches through the sequence.
    """
    best_start = 0
    best_matches = 0
    for start in range(len(chords) - loop_length + 1):
        pattern = chords[start:start + loop_length]
        matches = 0
        for i in range(start, len(chords)):
            if _chords_match(chords[i], pattern[(i - start) % loop_length]):
                matches += 1
            else:
                break
        if matches > best_matches:
            best_matches = matches
            best_start = start
    return chords[best_start:best_start + loop_length]


def predict_next_chords(
    input_chords: list[ChordGuess],
    tonal: TonalCenter,
    *,
    count: int,
    rng: random.Random | None = None,
) -> list[ChordGuess]:
    """Predict the next `count` chords based on input progression.

    Strategy:
    1. If input has a loop, repeat it
    2. Otherwise, use functional harmony transition probabilities
    """
    if rng is None:
        rng = random.Random(42)

    if not input_chords:
        quality = "minor" if tonal.mode == "minor" else "major"
        default = ChordGuess(
            root_pc=tonal.root_pc,
            quality=quality,
            score=1.0,
            pitch_classes=_chord_pitch_classes(tonal.root_pc, quality),
        )
        return [default] * count

    # Strategy 1: detect and repeat loop
    is_looping, loop_length = _detect_loop(input_chords)
    if is_looping and loop_length > 0:
        # Find where the loop pattern starts by matching the last chord
        # to determine the current phase within the loop
        pattern = _find_loop_pattern(input_chords, loop_length)
        # Determine where we are in the loop after the input ends
        # The last input chord corresponds to some position in the pattern
        last_root = input_chords[-1].root_pc
        phase = 0
        for i in range(loop_length):
            if pattern[i].root_pc == last_root:
                phase = (i + 1) % loop_length
                # Keep searching for the last occurrence to get correct phase
        # If last chord matches multiple positions, pick the one that makes
        # the continuation start from the right place
        result = []
        for i in range(count):
            result.append(pattern[(phase + i) % loop_length])
        return result

    # Strategy 2: functional harmony transitions
    transitions = _MAJOR_TRANSITIONS if tonal.mode == "major" else _MINOR_TRANSITIONS
    result: list[ChordGuess] = []
    current = input_chords[-1]

    for _ in range(count):
        degree = _chord_to_degree(current, tonal)

        # Find applicable transitions
        candidates = transitions.get(degree)
        if not candidates:
            # Degree not in table - find nearest known degree
            known_degrees = sorted(transitions.keys())
            nearest = min(known_degrees, key=lambda d: min(abs(d - degree), 12 - abs(d - degree)))
            candidates = transitions[nearest]

        # Weighted random selection
        total_weight = sum(w for _, w in candidates)
        roll = rng.random() * total_weight
        chosen_degree = candidates[0][0]
        cumulative = 0.0
        for next_degree, weight in candidates:
            cumulative += weight
            if roll <= cumulative:
                chosen_degree = next_degree
                break

        # Determine quality for chosen degree
        next_quality = _degree_to_chord_quality(chosen_degree, tonal.mode)

        # If the input had a dominant7 on V, preserve that flavor
        if chosen_degree == 7 and tonal.mode == "major":
            # V often becomes V7
            if any(c.quality == "dominant7" for c in input_chords if _chord_to_degree(c, tonal) == 7):
                next_quality = "dominant7"

        next_root = (tonal.root_pc + chosen_degree) % 12
        next_chord = ChordGuess(
            root_pc=next_root,
            quality=next_quality,
            score=1.0,
            pitch_classes=_chord_pitch_classes(next_root, next_quality),
        )
        result.append(next_chord)
        current = next_chord

    return result


# ---------------------------------------------------------------------------
# Motif / rhythm helpers
# ---------------------------------------------------------------------------

def _recent_motif_source_notes(
    notes: list[NoteEvent],
    *,
    context_seconds: float = 4.0,
    max_events: int = 10,
    seconds_per_measure: float = 0.0,
) -> list[NoteEvent]:
    if not notes:
        return [
            NoteEvent(note=60, velocity=80, time=0.0, duration=0.35),
            NoteEvent(note=62, velocity=78, time=0.5, duration=0.35),
            NoteEvent(note=64, velocity=84, time=1.0, duration=0.5),
            NoteEvent(note=67, velocity=76, time=1.75, duration=0.35),
        ]

    # When seconds_per_measure is provided, ensure motif covers at least 1 full measure
    effective_context = context_seconds
    effective_max = max_events
    if seconds_per_measure > 0:
        effective_context = max(context_seconds, seconds_per_measure)
        effective_max = max(10, int(seconds_per_measure / 0.15))

    phrase_end = max(note.time + note.duration for note in notes)
    start = max(0.0, phrase_end - max(0.25, effective_context))
    recent = [
        note
        for note in sorted(notes, key=lambda event: (event.time, event.note, event.duration))
        if note.time + note.duration > start
    ][-effective_max:]
    if not recent:
        recent = sorted(notes, key=lambda event: (event.time, event.note, event.duration))[-max_events:]

    motif_start = min(note.time for note in recent)
    # Group notes by onset, pick the highest pitch (melody voice) per onset
    onset_groups: dict[float, NoteEvent] = {}
    for note in recent:
        onset = round(max(0.0, note.time - motif_start), 3)
        if onset not in onset_groups or note.note > onset_groups[onset].note:
            onset_groups[onset] = note
    motif: list[NoteEvent] = []
    for onset in sorted(onset_groups):
        note = onset_groups[onset]
        motif.append(
            NoteEvent(
                note=note.note,
                velocity=int(note.velocity),
                time=onset,
                duration=round(max(0.08, note.duration), 3),
            )
        )

    if len(motif) < 2:
        previous = motif[-1] if motif else NoteEvent(note=60, velocity=80, time=0.0, duration=0.35)
        motif.append(
            NoteEvent(
                note=previous.note + 2,
                velocity=previous.velocity,
                time=round(previous.time + 0.5, 3),
                duration=0.35,
            )
        )
    return motif


def derive_rhythm_motif(
    notes: list[NoteEvent],
    *,
    context_seconds: float = 4.0,
    max_events: int = 10,
    seconds_per_measure: float = 0.0,
) -> list[tuple[float, float, int]]:
    return [
        (note.time, note.duration, note.velocity)
        for note in _recent_motif_source_notes(
            notes, context_seconds=context_seconds, max_events=max_events,
            seconds_per_measure=seconds_per_measure,
        )
    ]


# ---------------------------------------------------------------------------
# Pitch / register helpers
# ---------------------------------------------------------------------------

def _nearest_pitch(target: int, allowed_pitch_classes: list[int], low: int, high: int) -> int:
    candidates = [
        pitch
        for pitch in range(low, high + 1)
        if pitch % 12 in allowed_pitch_classes
    ]
    if not candidates:
        return max(low, min(high, target))
    return min(candidates, key=lambda pitch: (abs(pitch - target), pitch))


def _derive_register(notes: list[NoteEvent]) -> tuple[int, int, int]:
    if not notes:
        return (54, 74, 64)
    pitches = sorted(note.note for note in notes)
    center = int(round(sum(pitches) / len(pitches)))
    low = max(36, min(pitches) - 5)
    high = min(96, max(pitches) + 7)
    if high - low < 12:
        low = max(36, center - 8)
        high = min(96, center + 8)
    return low, high, center


# ---------------------------------------------------------------------------
# Texture analysis (multi-voice)
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class TextureProfile:
    """Describes the voicing density and register layout of the source material."""
    avg_density: float          # average notes per onset (1.0 = monophonic, 3.0 = triads)
    bass_low: int               # bass voice register bounds
    bass_high: int
    melody_low: int             # melody voice register bounds
    melody_high: int
    has_bass: bool              # whether source has a distinct bass layer
    has_chord: bool             # whether source has interior chord voicing
    onset_densities: list[int]  # density at each motif onset position
    measure_density_template: list[tuple[float, int]] = field(default_factory=list)  # (relative_time, density) per measure position


def _analyze_texture(
    notes: list[NoteEvent],
    *,
    context_seconds: float = 4.0,
    seconds_per_measure: float = 0.0,
) -> TextureProfile:
    """Analyze the voicing texture of recent source material.

    Determines how many notes typically occur per onset and what register
    layers (bass, chord, melody) are present.
    """
    if not notes:
        return TextureProfile(
            avg_density=1.0, bass_low=36, bass_high=48,
            melody_low=60, melody_high=84,
            has_bass=False, has_chord=False, onset_densities=[1],
        )

    phrase_end = max(n.time + n.duration for n in notes)

    # Register analysis uses a wider window (4-8 measures) for stable layer boundaries
    register_context = context_seconds
    if seconds_per_measure > 0:
        register_context = max(context_seconds, seconds_per_measure * 6)
    register_start = max(0.0, phrase_end - max(0.25, register_context))
    register_notes = [n for n in notes if n.time + n.duration > register_start]
    if not register_notes:
        register_notes = notes

    # Density / onset analysis uses a tighter window (2-4 measures)
    density_context = context_seconds
    if seconds_per_measure > 0:
        density_context = max(context_seconds, seconds_per_measure * 3)
    density_start = max(0.0, phrase_end - max(0.25, density_context))
    recent = [n for n in notes if n.time + n.duration > density_start]
    if not recent:
        recent = notes

    # Group notes by onset (within 30ms tolerance) — for density analysis
    onsets: list[list[NoteEvent]] = []
    recent_sorted = sorted(recent, key=lambda n: (n.time, n.note))
    current_group: list[NoteEvent] = []
    current_time = -1.0

    for note in recent_sorted:
        if current_time < 0 or abs(note.time - current_time) < 0.03:
            current_group.append(note)
            if current_time < 0:
                current_time = note.time
        else:
            if current_group:
                onsets.append(current_group)
            current_group = [note]
            current_time = note.time
    if current_group:
        onsets.append(current_group)

    if not onsets:
        return TextureProfile(
            avg_density=1.0, bass_low=36, bass_high=48,
            melody_low=60, melody_high=84,
            has_bass=False, has_chord=False, onset_densities=[1],
        )

    # Compute density per onset
    densities = [len(group) for group in onsets]
    avg_density = sum(densities) / len(densities)

    # Analyze register distribution — from the wider window for stability
    all_pitches = sorted(n.note for n in register_notes)
    lowest = all_pitches[0]
    highest = all_pitches[-1]
    pitch_range = highest - lowest

    # Determine if there's a clear bass/melody separation
    # Bass = notes in bottom 30% of range, Melody = top 30%
    has_bass = False
    has_chord = False
    bass_low = max(24, lowest)
    bass_high = lowest + max(12, pitch_range // 3)
    melody_low = highest - max(12, pitch_range // 3)
    melody_high = min(108, highest)

    # Use wider register_notes for layer detection (more stable boundaries)
    reg_onsets_count = max(len(onsets), 1)
    if pitch_range >= 24:
        # Wide enough range to have distinct layers
        bass_notes = [n for n in register_notes if n.note <= bass_high]
        melody_notes = [n for n in register_notes if n.note >= melody_low]
        mid_notes = [n for n in register_notes if bass_high < n.note < melody_low]

        has_bass = len(bass_notes) >= reg_onsets_count * 0.2
        has_chord = len(mid_notes) >= reg_onsets_count * 0.15 or avg_density >= 2.5
    elif pitch_range >= 12:
        # Medium range - might have bass or chord but not both
        center = (lowest + highest) // 2
        bass_high = center
        melody_low = center
        bass_notes = [n for n in register_notes if n.note < center]
        has_bass = len(bass_notes) >= reg_onsets_count * 0.25

    # Build onset density pattern (for the motif cycle)
    # Take the last N onsets that match what motif extraction would produce
    onset_densities = densities[-10:] if len(densities) > 10 else densities

    # Build per-measure-position density template when seconds_per_measure is known
    measure_density_template: list[tuple[float, int]] = []
    if seconds_per_measure > 0 and onsets:
        # Collect (relative_position_in_measure, density) for each onset
        # Quantize to 1/16 of a measure to merge nearby onsets (e.g., 16th notes)
        position_densities: dict[float, list[int]] = {}
        for group in onsets:
            onset_time = min(n.time for n in group)
            raw_rel = (onset_time % seconds_per_measure) / seconds_per_measure
            rel_pos = round(raw_rel * 16) / 16  # snap to 1/16 grid
            position_densities.setdefault(rel_pos, []).append(len(group))
        # Average densities at each position, then sort by position
        for pos in sorted(position_densities):
            vals = position_densities[pos]
            avg_d = round(sum(vals) / len(vals))
            measure_density_template.append((pos, max(1, avg_d)))

    return TextureProfile(
        avg_density=round(avg_density, 2),
        bass_low=bass_low,
        bass_high=bass_high,
        melody_low=melody_low,
        melody_high=melody_high,
        has_bass=has_bass,
        has_chord=has_chord,
        onset_densities=onset_densities,
        measure_density_template=measure_density_template,
    )


def _generate_voicing(
    *,
    melody_pitch: int,
    chord_pcs: list[int],
    scale_pcs: list[int],
    texture: TextureProfile,
    onset_index: int,
    duration: float,
    velocity: int,
    time_sec: float,
    strong: bool,
    prev_bass_pitch: int = 0,
    current_chord_root_pc: int = -1,
    prev_chord_root_pc: int = -1,
    seconds_per_measure: float = 0.0,
    beat_offset: float = 0.0,
    min_onset_gap: float = 0.0,
) -> tuple[list[NoteEvent], int]:
    """Generate multi-voice notes at a single onset point.

    Returns a tuple of (list of NoteEvents, bass_pitch used).
    bass_pitch is 0 if no bass was generated.
    """
    result = [NoteEvent(note=melody_pitch, velocity=velocity, time=time_sec, duration=duration)]

    # Determine target density for this onset
    # Prefer measure-position template when available
    if seconds_per_measure > 0 and texture.measure_density_template:
        # Account for beat_offset so density aligns with measure grid
        rel_pos = ((time_sec - beat_offset) % seconds_per_measure) / seconds_per_measure
        # Find nearest template entry
        best_entry = min(texture.measure_density_template, key=lambda entry: abs(entry[0] - rel_pos))
        target_density = best_entry[1]
    else:
        density_idx = onset_index % len(texture.onset_densities)
        target_density = texture.onset_densities[density_idx]

    # Cap density to avoid over-generation
    target_density = min(target_density, 4)

    bass_pitch_out = 0

    if target_density <= 1:
        return result, bass_pitch_out

    # Add bass note with voice leading
    bass_counted = False  # track for density even when skipping re-emit
    if texture.has_bass and target_density >= 2:
        root_pcs = [current_chord_root_pc] if current_chord_root_pc >= 0 else chord_pcs
        # First onset (prev_chord_root_pc < 0) counts as "new" so bass gets emitted
        chord_changed = (prev_chord_root_pc < 0
                         or (current_chord_root_pc >= 0 and prev_chord_root_pc >= 0
                             and current_chord_root_pc != prev_chord_root_pc))
        if prev_bass_pitch > 0 and not chord_changed:
            # Same chord: re-attack with shorter duration (matching source articulation)
            bass_pitch = prev_bass_pitch
            if bass_pitch != melody_pitch:
                bass_vel = max(40, velocity - 10)
                result.append(NoteEvent(note=bass_pitch, velocity=bass_vel, time=time_sec, duration=duration))
                bass_pitch_out = bass_pitch
                bass_counted = True
        elif prev_bass_pitch > 0:
            # Chord changed: move to new root via nearest pitch
            bass_pitch = _nearest_pitch(prev_bass_pitch, root_pcs, texture.bass_low, texture.bass_high)
            if bass_pitch != melody_pitch:
                bass_vel = max(40, velocity - 10)
                # Sustain longer but cap to avoid overlap with next onset
                max_dur = seconds_per_measure / 2 if seconds_per_measure > 0 else duration
                if min_onset_gap > 0:
                    max_dur = min(max_dur, min_onset_gap * 0.95)
                bass_dur = max(duration, max_dur)
                result.append(NoteEvent(note=bass_pitch, velocity=bass_vel, time=time_sec, duration=bass_dur))
                bass_pitch_out = bass_pitch
                bass_counted = True
        else:
            # No previous bass: start at register center on chord root
            bass_target = texture.bass_low + (texture.bass_high - texture.bass_low) // 2
            bass_pitch = _nearest_pitch(bass_target, root_pcs, texture.bass_low, texture.bass_high)
            if bass_pitch != melody_pitch:
                bass_vel = max(40, velocity - 10)
                max_dur = seconds_per_measure / 2 if seconds_per_measure > 0 else duration
                if min_onset_gap > 0:
                    max_dur = min(max_dur, min_onset_gap * 0.95)
                bass_dur = max(duration, max_dur)
                result.append(NoteEvent(note=bass_pitch, velocity=bass_vel, time=time_sec, duration=bass_dur))
                bass_pitch_out = bass_pitch
                bass_counted = True

    # Add chord interior notes
    if target_density >= 3 and (texture.has_chord or strong):
        # Fill between bass and melody with chord tones
        chord_low = texture.bass_high + 1
        chord_high = max(chord_low + 6, texture.melody_low - 1)
        # Account for bass toward density even when not re-emitted
        effective_count = len(result) + (1 if bass_counted and len(result) == 1 else 0)
        notes_to_add = min(target_density - effective_count, 2)
        chord_center = (chord_low + chord_high) // 2
        # Chord interior uses shorter stab duration
        chord_dur = min(duration, seconds_per_measure / 4) if seconds_per_measure > 0 else duration
        for i in range(notes_to_add):
            offset = (i - notes_to_add // 2) * 4
            target = chord_center + offset
            # Use chord tones on strong beats, scale tones on weak
            allowed = chord_pcs if strong else sorted(set(chord_pcs) | set(scale_pcs))
            interior_pitch = _nearest_pitch(target, allowed, chord_low, chord_high)
            # Avoid duplicating existing notes
            existing_pitches = {n.note for n in result}
            if interior_pitch not in existing_pitches:
                int_vel = max(40, velocity - 15)
                result.append(NoteEvent(note=interior_pitch, velocity=int_vel, time=time_sec, duration=chord_dur))

    return result, bass_pitch_out


# ---------------------------------------------------------------------------
# Beat position / timing helpers
# ---------------------------------------------------------------------------

def _is_strong_position(
    time_sec: float,
    response_seconds: float,
    seconds_per_measure: float = 2.0,
    beat_offset: float = 0.0,
) -> bool:
    """Determine if a time position is a 'strong' beat.

    Strong positions are: measure downbeats, and the final beat of the response.
    beat_offset aligns the measure grid so that time=beat_offset is a downbeat.
    """
    if seconds_per_measure > 0:
        # Position within current measure, adjusted for beat_offset
        pos_in_measure = (time_sec - beat_offset) % seconds_per_measure
        # Strong = within 8% of measure start (downbeat)
        if pos_in_measure < seconds_per_measure * 0.08 or pos_in_measure > seconds_per_measure * 0.92:
            return True
        # Also strong at half-measure (beat 3 in 4/4)
        half = seconds_per_measure / 2.0
        if abs(pos_in_measure - half) < seconds_per_measure * 0.08:
            return True
    else:
        beat = round((time_sec % 2.0) * 2) / 2
        if math.isclose(beat, 0.0, abs_tol=0.08):
            return True

    # Final moment of response is always strong (resolution)
    if time_sec >= response_seconds - 0.6:
        return True

    return False


def _compute_beat_offset(
    notes: list[NoteEvent],
    seconds_per_measure: float,
) -> float:
    """Calculate the time offset to start the reply at the next downbeat.

    Returns the gap (in seconds) between the end of the last note and
    the next measure boundary. If the user ended very close to a boundary
    (within 10%), returns 0.0.
    """
    if not notes or seconds_per_measure <= 0:
        return 0.0

    last_note_end = max(n.time + n.duration for n in notes)
    pos_in_measure = last_note_end % seconds_per_measure

    # How much time left until next measure start
    gap_to_next = seconds_per_measure - pos_in_measure

    # If very close to boundary already (within 10% of measure), skip the gap
    if pos_in_measure < seconds_per_measure * 0.10:
        return 0.0
    if gap_to_next < seconds_per_measure * 0.10:
        return 0.0

    # If the gap is very large (user stopped early in measure), we might want
    # to start at the next strong beat (half measure) instead of waiting
    half_measure = seconds_per_measure / 2.0
    if pos_in_measure < half_measure:
        # User stopped in first half - start at half measure (beat 3)
        gap_to_half = half_measure - pos_in_measure
        if gap_to_half < seconds_per_measure * 0.10:
            return 0.0
        return gap_to_half

    # User stopped in second half - start at next measure
    return gap_to_next


def _humanized_time(time_sec: float, style: str, index: int) -> float:
    timing = STYLE_RULES.get(style, STYLE_RULES["pop"])["timing"]
    if time_sec <= 0.0:
        return 0.0
    if timing == "behind":
        offset = 0.018 + (index % 2) * 0.006
    elif timing == "swing":
        offset = 0.025 if index % 2 else -0.004
    elif timing == "tight_16th":
        offset = (-0.006, 0.004, 0.0, 0.007)[index % 4]
    else:
        offset = (-0.008, 0.006, 0.0)[index % 3]
    return max(0.0, time_sec + offset)


def _styled_duration(duration: float, style: str) -> float:
    behavior = STYLE_RULES.get(style, STYLE_RULES["pop"])["duration"]
    if behavior == "staccato":
        return max(0.06, min(duration * 0.45, 0.22))
    if behavior == "short":
        return max(0.08, min(duration * 0.7, 0.4))
    if behavior == "legato":
        return max(0.2, min(duration * 1.25, 1.4))
    if behavior == "breathy":
        return max(0.1, min(duration * 0.9, 0.8))
    return max(0.1, min(duration, 0.75))


def _styled_velocity(base_velocity: int, style: str, index: int, strong: bool, *, flat_velocity: bool = False) -> int:
    if flat_velocity:
        # Source is essentially flat — suppress artificial contour
        accent = 5 if strong else 0
        micro = ((index * 3) % 5) - 2  # ±2 micro-variation
        velocity = int(base_velocity + accent + micro)
        return max(base_velocity - 5, min(base_velocity + 12, velocity))
    low, high = STYLE_RULES.get(style, STYLE_RULES["pop"])["velocity"]
    accent = 10 if strong else 0
    contour = ((index * 7) % 17) - 8
    velocity = int(base_velocity + accent + contour)
    return max(low, min(high, velocity))


def _avoid_prompt_fingerprint(
    pitch: int,
    *,
    start_time: float,
    duration: float,
    target: int,
    allowed_pitch_classes: list[int],
    low: int,
    high: int,
    prompt_fingerprints: set[tuple[int, float, float]],
) -> int:
    fingerprint = (pitch, round(start_time, 2), round(duration, 2))
    if fingerprint not in prompt_fingerprints:
        return pitch
    candidates = [
        candidate
        for candidate in range(low, high + 1)
        if candidate % 12 in allowed_pitch_classes
        and (candidate, round(start_time, 2), round(duration, 2)) not in prompt_fingerprints
    ]
    if not candidates:
        return pitch
    return min(candidates, key=lambda candidate: (abs(candidate - target), candidate))


# ---------------------------------------------------------------------------
# Main generation entry point
# ---------------------------------------------------------------------------

def run_rule_improviser(
    notes: list[NoteEvent],
    *,
    response_seconds: float,
    style: str = "pop",
    context_seconds: float = 4.0,
    mode: str = "rhythm_lock",
    seconds_per_measure: float = 0.0,
) -> RuleResult:
    """Generate a musical reply based on rule-based harmonic and rhythmic analysis.

    Args:
        notes: Input note events from the user's performance.
        response_seconds: Duration of the reply in seconds.
        style: Musical style preset.
        context_seconds: Window for motif extraction.
        mode: "rhythm_lock" (copy rhythm, revoice pitch) or "motif" (vary both).
        seconds_per_measure: Duration of one measure in seconds. If 0, uses a
            default of 2.0s. Used for beat alignment and per-measure chord analysis.
    """
    started = time.perf_counter()
    normalized_style = style if style in STYLE_RULES else "pop"
    normalized_mode = mode if mode in {"rhythm_lock", "motif"} else "rhythm_lock"
    rule = STYLE_RULES[normalized_style]

    # Effective measure length and whether we use multi-chord progression
    use_progression = seconds_per_measure > 0
    effective_spm = seconds_per_measure if seconds_per_measure > 0 else 2.0

    # ----- Tonal & chord analysis -----
    tonal = infer_tonal_center(notes)

    # Single-chord inference (always computed for backward compat and as fallback)
    single_chord = infer_chord_from_notes(notes, tonal, context_seconds=context_seconds)

    rng = random.Random(
        hash(tuple((note.note, round(note.time, 2), round(note.duration, 2)) for note in notes)) & 0xFFFFFFFF
    )

    # Per-measure chord analysis (only when seconds_per_measure is provided)
    if use_progression:
        input_duration = max(n.time + n.duration for n in notes) if notes else effective_spm
        input_measure_count = max(1, round(input_duration / effective_spm))
        input_chords = infer_chords_per_measure(
            notes, tonal,
            seconds_per_measure=effective_spm,
            total_measures=input_measure_count,
        )
        response_measure_count = max(1, math.ceil(response_seconds / effective_spm))
        predicted_chords = predict_next_chords(
            input_chords, tonal,
            count=response_measure_count,
            rng=rng,
        )
    else:
        input_chords = [single_chord]
        response_measure_count = 1
        predicted_chords = [single_chord]

    # ----- Beat offset (tail handling) -----
    beat_offset = _compute_beat_offset(notes, effective_spm) if use_progression else 0.0

    # ----- Scale & pitch classes per measure -----
    # Build a lookup: for each response measure, what chord and scale to use
    measure_scales: list[list[int]] = []
    measure_chord_pcs: list[list[int]] = []
    if use_progression:
        for chord in predicted_chords:
            full_scale = _scale_for_chord(chord, tonal, normalized_style)
            filtered_scale = _style_filtered_scale(full_scale, normalized_style)
            measure_scales.append(filtered_scale)
            measure_chord_pcs.append(list(chord.pitch_classes))
    else:
        # Single-chord fallback: same chord and scale for all
        fallback_scale = _style_scale(tonal.root_pc, tonal.mode, normalized_style)
        measure_scales = [fallback_scale]
        measure_chord_pcs = [list(single_chord.pitch_classes)]

    # Legacy single scale (for debug output and fallback)
    scale_pitch_classes = _style_scale(tonal.root_pc, tonal.mode, normalized_style)
    chord_pitch_classes = list(single_chord.pitch_classes)
    strong_pitch_classes = _pitch_class_set(tonal.root_pc, tuple(rule["strong_degrees"]))

    # ----- Register & motif -----
    low, high, center = _derive_register(notes)
    # Fix 1: pass effective_spm so motif covers at least one full measure
    motif_sources = _recent_motif_source_notes(
        notes, context_seconds=context_seconds, seconds_per_measure=effective_spm,
    )
    motif = [(note.time, note.duration, note.velocity) for note in motif_sources]

    # Fix 3: texture analysis with measure-aware context window
    texture = _analyze_texture(notes, context_seconds=context_seconds, seconds_per_measure=effective_spm)

    source_pitches = [note.note for note in sorted(notes, key=lambda event: (event.time, event.note))[-8:]]
    if not source_pitches:
        source_pitches = [center, center + 2, center + 4, center + 7]
    base_velocity = int(sum(note.velocity for note in notes) / len(notes)) if notes else 82

    # Fix 5: detect flat velocity profile from source
    if notes:
        src_velocities = [n.velocity for n in notes]
        velocity_spread = max(src_velocities) - min(src_velocities)
    else:
        velocity_spread = 30  # default: assume non-flat
    flat_velocity = velocity_spread < 15

    # Fix D: compute source articulation ratio (duration / inter-onset interval)
    source_artic_ratio = 0.0
    if len(motif) >= 2:
        ratios: list[float] = []
        for i in range(len(motif) - 1):
            ioi = motif[i + 1][0] - motif[i][0]
            if ioi > 0.02:
                ratios.append(min(1.0, motif[i][1] / ioi))
        if ratios:
            ratios.sort()
            source_artic_ratio = ratios[len(ratios) // 2]  # median

    # Fix 3: initialize melody pitch from texture layers, not all-note center
    prev_melody_pitch = (texture.melody_low + texture.melody_high) // 2

    # Fix 6: derive max_melody_step from source melody intervals
    max_melody_step = 7  # default fallback
    if notes:
        # Extract top voice at each onset from recent context
        phrase_end_t = max(n.time + n.duration for n in notes)
        ctx_start = max(0.0, phrase_end_t - max(0.25, context_seconds))
        ctx_notes = [n for n in notes if n.time + n.duration > ctx_start]
        if ctx_notes:
            # Group by onset time (30ms tolerance), pick highest note per onset
            ctx_sorted = sorted(ctx_notes, key=lambda n: (n.time, n.note))
            melody_onsets: list[int] = []
            grp_time = -1.0
            grp_high = 0
            for n in ctx_sorted:
                if grp_time < 0 or abs(n.time - grp_time) < 0.03:
                    if grp_time < 0:
                        grp_time = n.time
                    # Only consider melody-layer notes
                    if n.note >= texture.melody_low:
                        grp_high = max(grp_high, n.note)
                else:
                    if grp_high > 0:
                        melody_onsets.append(grp_high)
                    grp_time = n.time
                    grp_high = n.note if n.note >= texture.melody_low else 0
            if grp_high > 0:
                melody_onsets.append(grp_high)
            # Compute consecutive intervals
            if len(melody_onsets) >= 3:
                intervals = [abs(melody_onsets[i+1] - melody_onsets[i]) for i in range(len(melody_onsets) - 1)]
                intervals.sort()
                p75_idx = int(len(intervals) * 0.75)
                p75_val = intervals[min(p75_idx, len(intervals) - 1)]
                max_melody_step = max(5, min(12, p75_val))

    # Voice-leading state: track previous bass pitch
    # Initialize from source's lowest recent note
    prev_bass_pitch = 0
    if notes:
        recent_low = min(n.note for n in notes[-8:])
        if recent_low <= texture.bass_high:
            prev_bass_pitch = recent_low
    prev_chord_root_pc = -1

    # ----- Generation loop -----
    output: list[NoteEvent] = []
    prompt_fingerprints = {
        (note.note, round(note.time, 2), round(note.duration, 2))
        for note in notes
    }
    raw_cycle_len = max(motif[-1][0] + motif[-1][1], 0.5)
    # Snap cycle length to measure boundary to prevent drift
    if effective_spm > 0 and use_progression:
        measure_count = max(1, round(raw_cycle_len / effective_spm))
        cycle_len = effective_spm * measure_count
    else:
        cycle_len = raw_cycle_len
    # Compute minimum inter-onset interval from motif (for bass duration cap)
    if len(motif) >= 2:
        onset_gaps = [motif[i+1][0] - motif[i][0] for i in range(len(motif)-1) if motif[i+1][0] > motif[i][0]]
        min_onset_gap = min(onset_gaps) if onset_gaps else cycle_len
    else:
        min_onset_gap = cycle_len
    density = float(rule["density"])
    cycle_index = 0

    while True:
        cycle_start = beat_offset + cycle_index * cycle_len
        if cycle_start >= response_seconds:
            break
        for motif_index, (motif_onset, motif_duration, motif_velocity) in enumerate(motif):
            if (
                normalized_mode == "motif"
                and density < 1.0
                and (cycle_index + motif_index) % round(1 / max(0.25, 1.0 - density)) == 0
            ):
                if motif_index not in (0, len(motif) - 1):
                    continue
            time_sec = round(cycle_start + motif_onset, 3)
            if time_sec >= response_seconds:
                continue

            # Determine which response measure we're in (adjusted for beat_offset)
            response_measure_idx = min(
                max(0, int((time_sec - beat_offset) / effective_spm)),
                response_measure_count - 1,
            )

            # Get chord and scale for this measure
            current_chord_pcs = measure_chord_pcs[response_measure_idx]
            current_scale = measure_scales[response_measure_idx]
            current_chord = predicted_chords[response_measure_idx]

            strong = _is_strong_position(time_sec, response_seconds, effective_spm, beat_offset=beat_offset)
            direction = -1 if cycle_index % 2 else 1
            source_note = motif_sources[motif_index % len(motif_sources)]
            source_pitch = source_note.note if normalized_mode == "rhythm_lock" else source_pitches[(cycle_index + motif_index) % len(source_pitches)]

            if normalized_mode == "rhythm_lock":
                allowed = current_chord_pcs if strong else current_scale
                if not strong and normalized_style in {"blues", "rock", "funk"}:
                    allowed = sorted(set(allowed) | set(current_chord_pcs))
                target = source_pitch + direction * (4 if strong else 2 + (motif_index % 2) * 2)
                if motif_index == len(motif) - 1 or time_sec >= response_seconds - 0.5:
                    target = source_pitch + direction * 3
                    allowed = current_chord_pcs

                # Apply voice leading: constrain target near previous melody pitch
                melody_low = max(texture.melody_low, prev_melody_pitch - max_melody_step)
                melody_high = min(texture.melody_high, prev_melody_pitch + max_melody_step)
                # On strong beats allow slightly wider leaps
                if strong:
                    melody_low = max(texture.melody_low, prev_melody_pitch - max_melody_step - 3)
                    melody_high = min(texture.melody_high, prev_melody_pitch + max_melody_step + 3)
                # Ensure range is valid
                if melody_low > melody_high:
                    melody_low, melody_high = texture.melody_low, texture.melody_high

                pitch = _nearest_pitch(target, allowed, melody_low, melody_high)
                # Avoid repeated pitch on weak beats
                if pitch == prev_melody_pitch and not strong:
                    pitch = _nearest_pitch(pitch + direction * 2, allowed, melody_low, melody_high)
                start_time = time_sec
                duration = round(min(motif_duration, max(0.08, response_seconds - start_time)), 3)
                pitch = _avoid_prompt_fingerprint(
                    pitch,
                    start_time=start_time,
                    duration=duration,
                    target=target + direction * 4,
                    allowed_pitch_classes=allowed,
                    low=melody_low,
                    high=melody_high,
                    prompt_fingerprints=prompt_fingerprints,
                )
                velocity = _styled_velocity(motif_velocity, normalized_style, len(output), strong, flat_velocity=flat_velocity)
            else:
                target = source_pitch + direction * (2 + (motif_index % 3))
                current_strong_pcs = list(current_chord.pitch_classes)
                allowed = current_strong_pcs if strong else current_scale
                if normalized_style in {"funk", "blues", "rock"} and not strong:
                    target += rng.choice((-2, 0, 2))

                # Voice leading for motif mode
                melody_low = max(texture.melody_low, prev_melody_pitch - max_melody_step)
                melody_high = min(texture.melody_high, prev_melody_pitch + max_melody_step)
                if melody_low > melody_high:
                    melody_low, melody_high = texture.melody_low, texture.melody_high

                pitch = _nearest_pitch(target, allowed, melody_low, melody_high)
                if pitch == prev_melody_pitch and not strong:
                    pitch = _nearest_pitch(pitch + direction * 2, current_scale, melody_low, melody_high)

                start_time = _humanized_time(time_sec, normalized_style, len(output))
                # Preserve source articulation when available, fall back to style rules
                if source_artic_ratio > 0.05:
                    # motif_duration already carries source articulation; keep it
                    duration = min(motif_duration, max(0.08, response_seconds - start_time))
                else:
                    duration = min(_styled_duration(motif_duration, normalized_style), max(0.08, response_seconds - start_time))
                pitch = _avoid_prompt_fingerprint(
                    pitch,
                    start_time=start_time,
                    duration=duration,
                    target=pitch + direction * 4,
                    allowed_pitch_classes=allowed,
                    low=melody_low,
                    high=melody_high,
                    prompt_fingerprints=prompt_fingerprints,
                )
                velocity = _styled_velocity((base_velocity + motif_velocity) // 2, normalized_style, len(output), strong, flat_velocity=flat_velocity)

            # Update voice leading state
            prev_melody_pitch = pitch

            # Generate multi-voice output (melody + bass + chord interior)
            voicing, bass_used = _generate_voicing(
                melody_pitch=pitch,
                chord_pcs=current_chord_pcs,
                scale_pcs=current_scale,
                texture=texture,
                onset_index=motif_index + cycle_index * len(motif),
                duration=duration,
                velocity=velocity,
                time_sec=start_time,
                strong=strong,
                prev_bass_pitch=prev_bass_pitch,
                current_chord_root_pc=current_chord.root_pc,
                prev_chord_root_pc=prev_chord_root_pc,
                seconds_per_measure=effective_spm if use_progression else 0.0,
                beat_offset=beat_offset,
                min_onset_gap=min_onset_gap,
            )
            if bass_used > 0:
                prev_bass_pitch = bass_used
            prev_chord_root_pc = current_chord.root_pc
            output.extend(voicing)
        cycle_index += 1

    if output:
        # Find the last melody note (highest pitch at the last onset time)
        last_time = max(n.time for n in output)
        last_notes = [n for n in output if abs(n.time - last_time) < 0.01]
        melody_note = max(last_notes, key=lambda n: n.note)
        final_chord_pcs = measure_chord_pcs[-1] if measure_chord_pcs else chord_pitch_classes
        final_allowed = final_chord_pcs if normalized_mode == "rhythm_lock" else list(predicted_chords[-1].pitch_classes)
        final_pitch = _nearest_pitch(melody_note.note, final_allowed, texture.melody_low, texture.melody_high)
        # Replace the melody note with resolved pitch
        output = [n for n in output if n is not melody_note]
        output.append(NoteEvent(
            note=final_pitch,
            velocity=melody_note.velocity,
            time=melody_note.time,
            duration=melody_note.duration if normalized_mode == "rhythm_lock" else max(melody_note.duration, min(0.4, response_seconds - melody_note.time)),
        ))

    output.sort(key=lambda event: (event.time, event.note, event.duration))
    elapsed_ms = int((time.perf_counter() - started) * 1000)

    # ----- Build debug info -----
    is_looping, loop_length = _detect_loop(input_chords)
    return RuleResult(
        notes=output,
        timings={"generate_ms": elapsed_ms},
        debug={
            "mode": normalized_mode,
            "copied_rhythm": normalized_mode == "rhythm_lock",
            "style": normalized_style,
            "style_label": rule["label"],
            "root_pc": tonal.root_pc,
            "tonal_mode": tonal.mode,
            "chord": {
                "root_pc": single_chord.root_pc,
                "quality": single_chord.quality,
                "score": round(single_chord.score, 3),
                "pitch_classes": list(single_chord.pitch_classes),
            },
            "scale_pitch_classes": scale_pitch_classes,
            "strong_pitch_classes": chord_pitch_classes if normalized_mode == "rhythm_lock" else strong_pitch_classes,
            "register": {"low": low, "high": high, "center": center},
            "max_melody_step": max_melody_step,
            "velocity_spread": velocity_spread,
            "flat_velocity": flat_velocity,
            "motif": [{"time": item[0], "duration": item[1], "velocity": item[2]} for item in motif],
            "beat_offset": round(beat_offset, 4),
            "seconds_per_measure": round(effective_spm, 4),
            "progression": {
                "input_chords": [
                    {"root_pc": c.root_pc, "quality": c.quality, "pitch_classes": list(c.pitch_classes)}
                    for c in input_chords
                ],
                "predicted_chords": [
                    {"root_pc": c.root_pc, "quality": c.quality, "pitch_classes": list(c.pitch_classes)}
                    for c in predicted_chords
                ],
                "is_looping": is_looping,
                "loop_length": loop_length,
                "response_measures": response_measure_count,
            },
        },
    )
