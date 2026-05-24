from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


def _clamp_int(value: int, lower: int, upper: int) -> int:
    return max(lower, min(upper, value))


def _clamp_float(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


class DialogueNote(BaseModel):
    model_config = ConfigDict(extra="ignore")

    note: int = Field(ge=0, le=127)
    velocity: int = Field(ge=0, le=127)
    time: float = Field(ge=0)
    duration: float = Field(gt=0)


class GenerateParams(BaseModel):
    model_config = ConfigDict(extra="ignore")

    top_p: float = Field(default=0.95, ge=0.0, le=1.0)
    max_tokens: int = Field(default=256, ge=1, le=8192)
    strategy: str = "model"
    seed: int | None = None


class GenerateRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    type: str = "generate"
    protocol_version: int = 1
    notes: list[DialogueNote]
    params: GenerateParams = Field(default_factory=GenerateParams)
    session_id: str | None = None


class ResultResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    type: str = "result"
    protocol_version: int = 1
    notes: list[DialogueNote]
    latency_ms: int | None = None


class ErrorResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    type: str = "error"
    protocol_version: int = 1
    message: str


def legalize_notes(notes: list[DialogueNote]) -> list[DialogueNote]:
    legalized: list[DialogueNote] = []
    for note in notes:
        legalized.append(
            DialogueNote(
                note=_clamp_int(int(note.note), 0, 127),
                velocity=_clamp_int(int(note.velocity), 0, 127),
                time=_clamp_float(float(note.time), 0.0, 1_000_000.0),
                duration=_clamp_float(float(note.duration), 0.01, 1_000_000.0),
            )
        )
    legalized.sort(key=lambda item: (item.time, item.note))
    return legalized
