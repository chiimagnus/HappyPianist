from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


MODEL_ID = "Qwen3.5-0.8B-NF4-4bit"
ENGINE_ID = "qwen-companion"
PROTOCOL_VERSION = "2"
COMPANION_DECISION_PATH = "/v1/companion-decision"


class CompanionState(BaseModel):
    model_config = ConfigDict(extra="forbid")

    held_notes_count: int = Field(ge=0)
    sustain_value: int = Field(ge=0, le=127)
    recent_ioi_median_seconds: float | None = Field(default=None, ge=0)
    recent_note_density_per_second: float = Field(ge=0)
    seconds_since_last_note_on: float | None = Field(default=None, ge=0)
    is_ai_playback_active: bool
    user_note_on_since_ai_playback_started: bool


def companion_state_payload(state: dict[str, Any]) -> dict[str, Any]:
    return CompanionState.model_validate(state).model_dump()


class CompanionDecisionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    state: CompanionState


class SemanticValues(BaseModel):
    model_config = ConfigDict(extra="forbid")

    continuing: float = Field(ge=0, le=1)
    finished: float = Field(ge=0, le=1)
    space: float = Field(ge=0, le=1)
    reasserted: float = Field(ge=0, le=1)


CompanionAction = Literal["listen", "support", "sparse", "yield", "respond"]


class CompanionUsage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    input_tokens: int = Field(ge=0)
    output_tokens: Literal[0] = 0


class CompanionDecisionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: Literal[MODEL_ID] = MODEL_ID
    action: CompanionAction
    semantic_scores: SemanticValues
    semantic_order_gaps: SemanticValues
    usage: CompanionUsage
    server_latency_ms: int = Field(ge=0)


class CompanionErrorResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: str = Field(min_length=1)
    message: str | None = None
