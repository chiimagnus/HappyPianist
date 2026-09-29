from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


PROTOCOL_VERSION = 3
ALLOWED_CC_CONTROLLERS: set[int] = {7, 11, 64}


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class GenerateParams(StrictModel):
    max_tokens: int = Field(ge=1, le=8192)


class NoteEvent(StrictModel):
    type: Literal["note"] = "note"
    note: int = Field(ge=0, le=127)
    velocity: int = Field(ge=0, le=127)
    time: float = Field(ge=0)
    duration: float = Field(gt=0)


class ControlChangeEvent(StrictModel):
    type: Literal["cc"] = "cc"
    controller: Literal[7, 11, 64]
    value: int = Field(ge=0, le=127)
    time: float = Field(ge=0)


ImprovEvent = NoteEvent | ControlChangeEvent


class GenerateRequest(StrictModel):
    type: Literal["generate"] = "generate"
    protocol_version: Literal[PROTOCOL_VERSION] = PROTOCOL_VERSION
    events: list[ImprovEvent]
    params: GenerateParams

    @model_validator(mode="after")
    def require_observed_sustain_only(self) -> "GenerateRequest":
        if any(
            isinstance(event, ControlChangeEvent) and event.controller != 64
            for event in self.events
        ):
            raise ValueError("Aria prompt only accepts observed sustain CC64")
        return self


class ResultResponse(StrictModel):
    type: Literal["result"] = "result"
    protocol_version: Literal[PROTOCOL_VERSION] = PROTOCOL_VERSION
    events: list[ImprovEvent]
    latency_ms: int = Field(ge=0)


class ErrorResponse(StrictModel):
    type: Literal["error"] = "error"
    protocol_version: Literal[PROTOCOL_VERSION] = PROTOCOL_VERSION
    code: str = Field(min_length=1)
    message: str | None = None


def ordered_events(events: list[ImprovEvent]) -> list[ImprovEvent]:
    def sort_key(item: ImprovEvent) -> tuple[float, int, int, int]:
        if isinstance(item, ControlChangeEvent):
            return (item.time, 0, item.controller, item.value)
        return (item.time, 1, item.note, item.velocity)

    return sorted(events, key=sort_key)
