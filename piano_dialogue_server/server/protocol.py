from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


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


class GenerateRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    type: Literal["generate"] = "generate"
    protocol_version: int = 1
    notes: list[DialogueNote]
    params: GenerateParams = Field(default_factory=GenerateParams)
    session_id: str | None = None


class ResultResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    type: Literal["result"] = "result"
    protocol_version: int = 1
    notes: list[DialogueNote]
    latency_ms: int | None = None


class ErrorResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    type: Literal["error"] = "error"
    protocol_version: int = 1
    message: str

