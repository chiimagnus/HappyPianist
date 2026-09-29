from __future__ import annotations

from types import SimpleNamespace

import pytest

from scripts.companion_service_e2e import (
    E2E_CASES_PER_SOURCE_STATE,
    select_service_scenarios,
    technical_gate,
    validate_generated_events,
    validate_written_midi,
    write_midi,
)
from shared.aria_protocol import GenerateParams, GenerateRequest, NoteEvent


def test_select_service_scenarios_takes_first_five_per_source_state() -> None:
    scenarios = []
    for source in ("maestro", "pop909"):
        for state in (
            "active_dense",
            "active_sparse",
            "natural_silence",
            "settled_end",
            "sustain_pause",
            "takeover_overlay",
        ):
            for index in range(10):
                scenarios.append(
                    SimpleNamespace(
                        source=source,
                        name=state,
                        case_id=f"{source}|{state}|{index}",
                    )
                )

    selected = select_service_scenarios(scenarios)
    assert len(selected) == 60
    assert E2E_CASES_PER_SOURCE_STATE == 5
    for source in ("maestro", "pop909"):
        for state in (
            "active_dense",
            "active_sparse",
            "natural_silence",
            "settled_end",
            "sustain_pause",
            "takeover_overlay",
        ):
            ids = [
                item.case_id
                for item in selected
                if item.source == source and item.name == state
            ]
            assert ids == [f"{source}|{state}|{index}" for index in range(5)]


def test_generated_events_write_and_reparse_with_balanced_notes(tmp_path) -> None:
    request = GenerateRequest(
        events=[
            NoteEvent(note=60, velocity=80, time=0.0, duration=0.2),
            NoteEvent(note=62, velocity=82, time=0.3, duration=0.2),
            NoteEvent(note=64, velocity=84, time=0.6, duration=0.2),
            NoteEvent(note=65, velocity=86, time=0.9, duration=0.2),
        ],
        params=GenerateParams(max_tokens=64),
    )
    generated = [
        NoteEvent(note=67, velocity=90, time=0.0, duration=0.25),
        NoteEvent(note=69, velocity=92, time=0.3, duration=0.25),
    ]

    validation = validate_generated_events(request, generated)
    assert validation["note_count"] == 2

    path = tmp_path / "generated.mid"
    write_midi(generated, path)
    midi_validation = validate_written_midi(path)
    assert midi_validation == {
        "midi_note_on_count": 2,
        "midi_note_off_count": 2,
    }


def test_generated_events_reject_prompt_echo() -> None:
    prompt = [
        NoteEvent(note=60 + index, velocity=80, time=index * 0.2, duration=0.1)
        for index in range(4)
    ]
    request = GenerateRequest(
        events=prompt,
        params=GenerateParams(max_tokens=64),
    )

    with pytest.raises(AssertionError, match="echo"):
        validate_generated_events(request, list(prompt))


def test_technical_gate_accepts_matching_decision_and_successful_generation() -> None:
    rows = [
        {
            "case_id": "case-a",
            "action": "support",
            "generation_attempted": True,
            "generated": True,
        },
        {
            "case_id": "case-b",
            "action": "listen",
            "generation_attempted": False,
            "generated": False,
        },
    ]
    gate = technical_gate(
        rows,
        reference_actions={"case-a": "support", "case-b": "listen"},
    )
    assert gate["passed"] is True
    assert gate["reasons"] == []


def test_technical_gate_rejects_action_mismatch_and_generation_failure() -> None:
    rows = [
        {
            "case_id": "case-a",
            "action": "support",
            "generation_attempted": True,
            "generated": False,
            "generation_error": "RuntimeError: aria failed",
        },
        {
            "case_id": "case-b",
            "action": "listen",
            "generation_attempted": False,
            "generated": False,
        },
    ]
    gate = technical_gate(
        rows,
        reference_actions={"case-a": "sparse", "case-b": "listen"},
    )
    assert gate["passed"] is False
    assert "stage_a_action_mismatches:1" in gate["reasons"]
    assert "generation_failures:1" in gate["reasons"]
