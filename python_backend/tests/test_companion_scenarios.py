from __future__ import annotations

import json
from pathlib import Path

from python_backend.shared.companion_scenarios import (
    PROJECTION_VERSION,
    ParsedCC,
    ParsedMIDI,
    ParsedNote,
    ProjectionEvent,
    project_qwen_state,
    sample_scenarios,
)


FIXTURE = (
    Path(__file__).resolve().parents[2]
    / "Packages/HappyPianistCore/Sources/HappyPianistTestFixtures/Resources/Fixtures/CompanionQwenStateProjection.json"
)


def _parsed(case: dict) -> ParsedMIDI:
    active: dict[int, tuple[float, int]] = {}
    notes: list[ParsedNote] = []
    ccs: list[ParsedCC] = []
    projection_events: list[ProjectionEvent] = []
    for sequence, event in enumerate(case["events"]):
        if event["type"] == "note_on":
            note = int(event["note"])
            velocity = int(event["velocity"])
            active[note] = (float(event["time"]), velocity)
            projection_events.append(
                ProjectionEvent(
                    time=float(event["time"]),
                    sequence=sequence,
                    kind="note_on",
                    note=note,
                    velocity=velocity,
                )
            )
        elif event["type"] == "note_off":
            note = int(event["note"])
            start, velocity = active.pop(note)
            projection_events.append(
                ProjectionEvent(
                    time=float(event["time"]),
                    sequence=sequence,
                    kind="note_off",
                    note=note,
                )
            )
            notes.append(
                ParsedNote(
                    note=note,
                    velocity=velocity,
                    start=start,
                    duration=float(event["time"]) - start,
                )
            )
        elif event["type"] == "cc64":
            value = int(event["value"])
            ccs.append(
                ParsedCC(
                    controller=64,
                    value=value,
                    time=float(event["time"]),
                )
            )
            projection_events.append(
                ProjectionEvent(
                    time=float(event["time"]),
                    sequence=sequence,
                    kind="cc64",
                    value=value,
                )
            )
        else:
            raise AssertionError(f"unsupported fixture event: {event}")
    for note, (start, velocity) in active.items():
        notes.append(
            ParsedNote(
                note=note,
                velocity=velocity,
                start=start,
                duration=max(0.01, float(case["snapshot_time"]) - start),
            )
        )
    return ParsedMIDI(
        notes=sorted(notes, key=lambda item: (item.start, item.note)),
        ccs=ccs,
        projection_events=projection_events,
        duration=float(case["snapshot_time"]),
    )


def test_sample_scenarios_uses_one_case_per_file_within_source_state() -> None:
    corpus = {
        "files": {"maestro": 3},
        "candidates": [
            {"source": "maestro", "state": "active_dense", "file": "a.mid", "timestamp": 1.0, "provenance": "x"},
            {"source": "maestro", "state": "active_dense", "file": "a.mid", "timestamp": 2.0, "provenance": "x"},
            {"source": "maestro", "state": "active_dense", "file": "b.mid", "timestamp": 3.0, "provenance": "x"},
            {"source": "maestro", "state": "active_dense", "file": "c.mid", "timestamp": 4.0, "provenance": "x"},
        ],
    }

    sampled = sample_scenarios(
        corpus,
        states={"active_dense"},
        cases_per_state_per_source=3,
        seed=42,
    )

    assert len(sampled) == 3
    assert len({scenario.file for scenario in sampled}) == 3


def test_python_qwen_state_projection_matches_canonical_fixture() -> None:
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    assert fixture["projection_version"] == PROJECTION_VERSION

    for case in fixture["cases"]:
        actual = project_qwen_state(
            _parsed(case),
            float(case["snapshot_time"]),
            is_ai_playback_active=bool(case["is_ai_playback_active"]),
            user_note_on_since_ai_playback_started=bool(
                case["user_note_on_since_ai_playback_started"]
            ),
        )
        expected = case["expected"]
        assert actual.keys() == expected.keys(), case["id"]
        for key, expected_value in expected.items():
            actual_value = actual[key]
            if isinstance(expected_value, float):
                assert abs(float(actual_value) - expected_value) < 1e-9, (case["id"], key)
            else:
                assert actual_value == expected_value, (case["id"], key)
