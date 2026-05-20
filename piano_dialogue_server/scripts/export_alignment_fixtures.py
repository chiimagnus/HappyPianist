from __future__ import annotations

import json
from pathlib import Path
import sys
import random
import time
import math

server_root = Path(__file__).resolve().parents[1]
if str(server_root) not in sys.path:
    sys.path.insert(0, str(server_root))

from server.api.protocol import DialogueNote, GenerateParams
from server.media.midi_generation import NoteEvent, analyze_dialogue_notes, generate_expanded_midi
from server.media.midi_utils import NoteEvent as RuleNoteEvent
from server.engines import rule_backend


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
    rule_dir = (
        Path(__file__).resolve().parents[2]
        / "LonelyPianistAVPTests"
        / "Improv"
        / "RuleFixtures"
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

    export_rule_fixture(
        notes=notes,
        params=params,
        session_id="fixture-1",
        seed=seed,
        output_path=rule_dir / "rule-fixture-1.json",
    )
def _max_phrase_end_sec(notes: list[DialogueNote]) -> float:
    if not notes:
        return 0.0
    return max(float(note.time + note.duration) for note in notes)


def _derive_rule_response_length_sec(params: GenerateParams) -> float:
    sec = params.max_tokens / 64.0
    return max(2.0, min(sec, 12.0))


def run_rule_improviser_seeded(
    notes: list[RuleNoteEvent],
    *,
    response_seconds: float,
    style: str = "pop",
    context_seconds: float = 4.0,
    mode: str = "rhythm_lock",
    seconds_per_measure: float = 0.0,
    seed: int,
) -> rule_backend.RuleResult:
    started = time.perf_counter()
    normalized_style = style if style in rule_backend.STYLE_RULES else "pop"
    normalized_mode = mode if mode in {"rhythm_lock", "motif"} else "rhythm_lock"
    rule = rule_backend.STYLE_RULES[normalized_style]

    use_progression = seconds_per_measure > 0
    effective_spm = seconds_per_measure if seconds_per_measure > 0 else 2.0

    tonal = rule_backend.infer_tonal_center(notes)
    single_chord = rule_backend.infer_chord_from_notes(notes, tonal, context_seconds=context_seconds)

    rng = random.Random(seed)

    if use_progression:
        input_duration = max(n.time + n.duration for n in notes) if notes else effective_spm
        input_measure_count = max(1, round(input_duration / effective_spm))
        input_chords = rule_backend.infer_chords_per_measure(
            notes,
            tonal,
            seconds_per_measure=effective_spm,
            total_measures=input_measure_count,
        )
        response_measure_count = max(1, math.ceil(response_seconds / effective_spm))
        predicted_chords = rule_backend.predict_next_chords(
            input_chords,
            tonal,
            count=response_measure_count,
            rng=rng,
        )
    else:
        input_chords = [single_chord]
        response_measure_count = 1
        predicted_chords = [single_chord]

    beat_offset = rule_backend._compute_beat_offset(notes, effective_spm) if use_progression else 0.0

    measure_scales: list[list[int]] = []
    measure_chord_pcs: list[list[int]] = []
    if use_progression:
        for chord in predicted_chords:
            full_scale = rule_backend._scale_for_chord(chord, tonal, normalized_style)
            filtered_scale = rule_backend._style_filtered_scale(full_scale, normalized_style)
            measure_scales.append(filtered_scale)
            measure_chord_pcs.append(list(chord.pitch_classes))
    else:
        fallback_scale = rule_backend._style_scale(tonal.root_pc, tonal.mode, normalized_style)
        measure_scales = [fallback_scale]
        measure_chord_pcs = [list(single_chord.pitch_classes)]

    chord_pitch_classes = list(single_chord.pitch_classes)
    strong_pitch_classes = rule_backend._pitch_class_set(tonal.root_pc, tuple(rule["strong_degrees"]))

    low, high, center = rule_backend._derive_register(notes)
    motif_sources = rule_backend._recent_motif_source_notes(
        notes, context_seconds=context_seconds, seconds_per_measure=effective_spm,
    )
    motif = [(note.time, note.duration, note.velocity) for note in motif_sources]

    texture = rule_backend._analyze_texture(notes, context_seconds=context_seconds, seconds_per_measure=effective_spm)

    source_pitches = [note.note for note in sorted(notes, key=lambda event: (event.time, event.note))[-8:]]
    if not source_pitches:
        source_pitches = [center, center + 2, center + 4, center + 7]
    base_velocity = int(sum(note.velocity for note in notes) / len(notes)) if notes else 82

    if notes:
        src_velocities = [n.velocity for n in notes]
        velocity_spread = max(src_velocities) - min(src_velocities)
    else:
        velocity_spread = 30
    flat_velocity = velocity_spread < 15

    source_artic_ratio = 0.0
    if len(motif) >= 2:
        ratios: list[float] = []
        for i in range(len(motif) - 1):
            ioi = motif[i + 1][0] - motif[i][0]
            if ioi > 0.02:
                ratios.append(min(1.0, motif[i][1] / ioi))
        if ratios:
            ratios.sort()
            source_artic_ratio = ratios[len(ratios) // 2]

    prev_melody_pitch = (texture.melody_low + texture.melody_high) // 2

    max_melody_step = 7
    if notes:
        phrase_end_t = max(n.time + n.duration for n in notes)
        ctx_start = max(0.0, phrase_end_t - max(0.25, context_seconds))
        ctx_notes = [n for n in notes if n.time + n.duration > ctx_start]
        if ctx_notes:
            ctx_sorted = sorted(ctx_notes, key=lambda n: (n.time, n.note))
            melody_onsets: list[int] = []
            grp_time = -1.0
            grp_high = 0
            for n in ctx_sorted:
                if grp_time < 0 or abs(n.time - grp_time) < 0.03:
                    if grp_time < 0:
                        grp_time = n.time
                    if n.note >= texture.melody_low:
                        grp_high = max(grp_high, n.note)
                else:
                    if grp_high > 0:
                        melody_onsets.append(grp_high)
                    grp_time = n.time
                    grp_high = n.note if n.note >= texture.melody_low else 0
            if grp_high > 0:
                melody_onsets.append(grp_high)
            if len(melody_onsets) >= 3:
                intervals = [abs(melody_onsets[i+1] - melody_onsets[i]) for i in range(len(melody_onsets) - 1)]
                intervals.sort()
                p75_idx = int(len(intervals) * 0.75)
                p75_val = intervals[min(p75_idx, len(intervals) - 1)]
                max_melody_step = max(5, min(12, p75_val))

    prev_bass_pitch = 0
    if notes:
        recent_low = min(n.note for n in notes[-8:])
        if recent_low <= texture.bass_high:
            prev_bass_pitch = recent_low
    prev_chord_root_pc = -1

    output: list[RuleNoteEvent] = []
    prompt_fingerprints = {
        (note.note, round(note.time, 2), round(note.duration, 2))
        for note in notes
    }
    raw_cycle_len = max(motif[-1][0] + motif[-1][1], 0.5)
    if effective_spm > 0 and use_progression:
        measure_count = max(1, round(raw_cycle_len / effective_spm))
        cycle_len = effective_spm * measure_count
    else:
        cycle_len = raw_cycle_len

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

            response_measure_idx = min(
                max(0, int((time_sec - beat_offset) / effective_spm)),
                response_measure_count - 1,
            )

            current_chord_pcs = measure_chord_pcs[response_measure_idx]
            current_scale = measure_scales[response_measure_idx]
            current_chord = predicted_chords[response_measure_idx]

            strong = rule_backend._is_strong_position(time_sec, response_seconds, effective_spm, beat_offset=beat_offset)
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

                melody_low = max(texture.melody_low, prev_melody_pitch - max_melody_step)
                melody_high = min(texture.melody_high, prev_melody_pitch + max_melody_step)
                if strong:
                    melody_low = max(texture.melody_low, prev_melody_pitch - max_melody_step - 3)
                    melody_high = min(texture.melody_high, prev_melody_pitch + max_melody_step + 3)
                if melody_low > melody_high:
                    melody_low, melody_high = texture.melody_low, texture.melody_high

                pitch = rule_backend._nearest_pitch(target, allowed, melody_low, melody_high)
                if pitch == prev_melody_pitch and not strong:
                    pitch = rule_backend._nearest_pitch(pitch + direction * 2, allowed, melody_low, melody_high)
                start_time = time_sec
                duration = round(min(motif_duration, max(0.08, response_seconds - start_time)), 3)
                pitch = rule_backend._avoid_prompt_fingerprint(
                    pitch,
                    start_time=start_time,
                    duration=duration,
                    target=target + direction * 4,
                    allowed_pitch_classes=allowed,
                    low=melody_low,
                    high=melody_high,
                    prompt_fingerprints=prompt_fingerprints,
                )
                velocity = rule_backend._styled_velocity(motif_velocity, normalized_style, len(output), strong, flat_velocity=flat_velocity)
            else:
                target = source_pitch + direction * (2 + (motif_index % 3))
                current_strong_pcs = list(current_chord.pitch_classes)
                allowed = current_strong_pcs if strong else current_scale
                if normalized_style in {"funk", "blues", "rock"} and not strong:
                    target += rng.choice((-2, 0, 2))

                melody_low = max(texture.melody_low, prev_melody_pitch - max_melody_step)
                melody_high = min(texture.melody_high, prev_melody_pitch + max_melody_step)
                if melody_low > melody_high:
                    melody_low, melody_high = texture.melody_low, texture.melody_high

                pitch = rule_backend._nearest_pitch(target, allowed, melody_low, melody_high)
                if pitch == prev_melody_pitch and not strong:
                    pitch = rule_backend._nearest_pitch(pitch + direction * 2, current_scale, melody_low, melody_high)

                start_time = rule_backend._humanized_time(time_sec, normalized_style, len(output))
                if source_artic_ratio > 0.05:
                    duration = min(motif_duration, max(0.08, response_seconds - start_time))
                else:
                    duration = min(rule_backend._styled_duration(motif_duration, normalized_style), max(0.08, response_seconds - start_time))
                pitch = rule_backend._avoid_prompt_fingerprint(
                    pitch,
                    start_time=start_time,
                    duration=duration,
                    target=pitch + direction * 4,
                    allowed_pitch_classes=allowed,
                    low=melody_low,
                    high=melody_high,
                    prompt_fingerprints=prompt_fingerprints,
                )
                velocity = rule_backend._styled_velocity((base_velocity + motif_velocity) // 2, normalized_style, len(output), strong, flat_velocity=flat_velocity)

            prev_melody_pitch = pitch

            voicing, bass_used = rule_backend._generate_voicing(
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
        last_time = max(n.time for n in output)
        last_notes = [n for n in output if abs(n.time - last_time) < 0.01]
        melody_note = max(last_notes, key=lambda n: n.note)
        final_chord_pcs = measure_chord_pcs[-1] if measure_chord_pcs else chord_pitch_classes
        final_allowed = final_chord_pcs if normalized_mode == "rhythm_lock" else list(predicted_chords[-1].pitch_classes)
        final_pitch = rule_backend._nearest_pitch(melody_note.note, final_allowed, texture.melody_low, texture.melody_high)
        output = [n for n in output if n is not melody_note]
        output.append(RuleNoteEvent(
            note=final_pitch,
            velocity=melody_note.velocity,
            time=melody_note.time,
            duration=melody_note.duration if normalized_mode == "rhythm_lock" else max(melody_note.duration, min(0.4, response_seconds - melody_note.time)),
        ))

    output.sort(key=lambda event: (event.time, event.note, event.duration))
    elapsed_ms = int((time.perf_counter() - started) * 1000)

    return rule_backend.RuleResult(
        notes=output,
        timings={"generate_ms": elapsed_ms},
        debug={},
    )


def export_rule_fixture(
    *,
    notes: list[DialogueNote],
    params: GenerateParams,
    session_id: str | None,
    seed: int,
    output_path: Path,
) -> None:
    input_events = [
        RuleNoteEvent(
            note=int(note.note),
            velocity=int(note.velocity),
            time=float(note.time),
            duration=float(note.duration),
        )
        for note in notes
    ]
    response_seconds = _derive_rule_response_length_sec(params)
    context_seconds = min(8.0, _max_phrase_end_sec(notes) + 1.0)

    result = run_rule_improviser_seeded(
        input_events,
        response_seconds=response_seconds,
        style="pop",
        context_seconds=context_seconds,
        mode="motif",
        seconds_per_measure=0.0,
        seed=seed,
    )

    payload: dict[str, object] = {
        "notes": [note.model_dump() for note in notes],
        "params": {
            "top_p": params.top_p,
            "max_tokens": params.max_tokens,
            "strategy": params.strategy,
            "seed": seed,
        },
        "session_id": session_id,
        "expected_notes": [event.as_dict() for event in result.notes],
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


if __name__ == "__main__":
    main()
