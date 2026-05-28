from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


def _clamp_int(value: int, lower: int, upper: int) -> int:
    return max(lower, min(upper, value))


def _clamp_float(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


class GenerateParams(BaseModel):
    model_config = ConfigDict(extra="ignore")

    top_p: float = Field(default=0.95, ge=0.0, le=1.0)
    max_tokens: int = Field(default=256, ge=1, le=8192)
    strategy: str = "model"
    seed: int | None = None


class NoteEvent(BaseModel):
    model_config = ConfigDict(extra="ignore")

    type: Literal["note"] = "note"
    note: int = Field(ge=0, le=127)
    velocity: int = Field(ge=0, le=127)
    time: float = Field(ge=0)
    duration: float = Field(ge=0)


class ControlChangeEvent(BaseModel):
    model_config = ConfigDict(extra="ignore")

    type: Literal["cc"] = "cc"
    controller: int = Field(ge=0, le=127)
    value: int = Field(ge=0, le=127)
    time: float = Field(ge=0)


ImprovEvent = NoteEvent | ControlChangeEvent


class GenerateRequestV2(BaseModel):
    model_config = ConfigDict(extra="ignore")

    type: str = "generate"
    protocol_version: Literal[2] = 2
    events: list[ImprovEvent]
    params: GenerateParams = Field(default_factory=GenerateParams)
    session_id: str | None = None


class ResultResponseV2(BaseModel):
    model_config = ConfigDict(extra="ignore")

    type: str = "result"
    protocol_version: Literal[2] = 2
    events: list[ImprovEvent]
    latency_ms: int | None = None


class ErrorResponseV2(BaseModel):
    model_config = ConfigDict(extra="ignore")

    type: str = "error"
    protocol_version: Literal[2] = 2
    message: str


ALLOWED_CC_CONTROLLERS: set[int] = {7, 11, 64}


def legalize_events(events: list[ImprovEvent]) -> list[ImprovEvent]:
    legalized: list[ImprovEvent] = []

    for event in events:
        if isinstance(event, NoteEvent):
            legalized.append(
                NoteEvent(
                    note=_clamp_int(int(event.note), 0, 127),
                    velocity=_clamp_int(int(event.velocity), 0, 127),
                    time=_clamp_float(float(event.time), 0.0, 1_000_000.0),
                    duration=_clamp_float(float(event.duration), 0.0, 1_000_000.0),
                )
            )
        elif isinstance(event, ControlChangeEvent):
            controller = _clamp_int(int(event.controller), 0, 127)
            if controller not in ALLOWED_CC_CONTROLLERS:
                continue
            legalized.append(
                ControlChangeEvent(
                    controller=controller,
                    value=_clamp_int(int(event.value), 0, 127),
                    time=_clamp_float(float(event.time), 0.0, 1_000_000.0),
                )
            )

    def sort_key(item: ImprovEvent) -> tuple[float, int, int, int]:
        if isinstance(item, ControlChangeEvent):
            # CC first at the same timestamp.
            return (item.time, 0, item.controller, item.value)
        return (item.time, 1, item.note, item.velocity)

    legalized.sort(key=sort_key)
    return legalized
