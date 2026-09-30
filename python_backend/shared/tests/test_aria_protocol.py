from __future__ import annotations

import math

import pytest
from pydantic import ValidationError

from shared.aria_protocol import (
    PROTOCOL_VERSION,
    ControlChangeEvent,
    GenerateRequest,
    NoteEvent,
    ResultResponse,
)


def _request_payload() -> dict:
    return {
        "type": "generate",
        "protocol_version": PROTOCOL_VERSION,
        "events": [
            {"type": "note", "note": 60, "velocity": 90, "time": 0.0, "duration": 0.25},
            {"type": "cc", "controller": 64, "value": 127, "time": 0.1},
        ],
        "params": {"max_tokens": 64},
    }


def test_generate_request_accepts_only_current_schema_and_prompt_cc64() -> None:
    request = GenerateRequest.model_validate(_request_payload())
    assert request.protocol_version == PROTOCOL_VERSION
    assert request.params.max_tokens == 64

    with pytest.raises(ValidationError):
        GenerateRequest.model_validate({**_request_payload(), "session_id": "legacy"})
    with pytest.raises(ValidationError):
        GenerateRequest.model_validate(
            {**_request_payload(), "params": {"max_tokens": 64, "top_p": 0.9}}
        )
    with pytest.raises(ValidationError):
        GenerateRequest.model_validate(
            {
                **_request_payload(),
                "events": [{"type": "cc", "controller": 7, "value": 100, "time": 0.0}],
            }
        )


def test_generate_request_rejects_nonfinite_out_of_range_and_wrong_protocol() -> None:
    invalid_events = [
        {"type": "note", "note": 128, "velocity": 90, "time": 0.0, "duration": 0.25},
        {"type": "note", "note": 60, "velocity": 128, "time": 0.0, "duration": 0.25},
        {"type": "note", "note": 60, "velocity": 90, "time": -0.1, "duration": 0.25},
        {"type": "note", "note": 60, "velocity": 90, "time": 0.0, "duration": 0.0},
        {"type": "note", "note": 60, "velocity": 90, "time": math.inf, "duration": 0.25},
    ]
    for event in invalid_events:
        with pytest.raises(ValidationError):
            GenerateRequest.model_validate({**_request_payload(), "events": [event]})

    with pytest.raises(ValidationError):
        GenerateRequest.model_validate({**_request_payload(), "protocol_version": 2})
    with pytest.raises(ValidationError):
        GenerateRequest.model_validate({**_request_payload(), "params": {"max_tokens": 0}})
    with pytest.raises(ValidationError):
        GenerateRequest.model_validate({**_request_payload(), "params": {"max_tokens": 8193}})


def test_result_response_allows_explicit_output_cc_policy_controllers() -> None:
    response = ResultResponse(
        events=[
            ControlChangeEvent(controller=7, value=100, time=0),
            ControlChangeEvent(controller=11, value=90, time=0),
            ControlChangeEvent(controller=64, value=127, time=0.1),
            NoteEvent(note=60, velocity=90, time=0.2, duration=0.25),
        ],
        latency_ms=12,
    )
    payload = response.model_dump()
    assert payload["protocol_version"] == PROTOCOL_VERSION
    assert [event["controller"] for event in payload["events"][:3]] == [7, 11, 64]
