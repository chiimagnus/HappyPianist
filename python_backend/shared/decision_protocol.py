from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


CompanionAction = Literal["listen", "support", "sparse", "yield", "respond"]


class DecisionNote(BaseModel):
    model_config = ConfigDict(extra="forbid")

    midi: int = Field(ge=0, le=127)
    velocity: int = Field(ge=0, le=127)
    onset_seconds_ago: float = Field(ge=0)
    duration_seconds: float = Field(ge=0)


class CompanionDecisionInputV2(BaseModel):
    model_config = ConfigDict(extra="forbid")

    now_timestamp_seconds: float
    held_notes_count: int = Field(ge=0)
    sustain_value: int = Field(ge=0, le=127)
    recent_ioi_median_seconds: float | None
    recent_velocity_trend: float
    recent_note_density_per_second: float = Field(ge=0)
    last_user_event_timestamp_seconds: float | None
    last_note_on_timestamp_seconds: float | None
    active_pitch_center: float | None
    is_ai_playback_active: bool
    recent_notes: list[DecisionNote] = Field(default_factory=list, max_length=32)


class DecisionRequestV2(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocol_version: Literal[2] = 2
    input: CompanionDecisionInputV2


class DecisionResponseV2(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocol_version: Literal[2] = 2
    action: CompanionAction
    confidence: float = Field(ge=0, le=1)
    probabilities: dict[str, float]
    latency_ms: int = Field(ge=0)
    model: str


class DecisionErrorResponseV2(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocol_version: Literal[2] = 2
    message: str
