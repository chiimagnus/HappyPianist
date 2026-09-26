from __future__ import annotations

from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class ChoiceQuestion(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["choice"] = "choice"
    instructions: str = Field(min_length=1)
    criteria: dict[str, str | None] | list[str]

    @field_validator("criteria")
    @classmethod
    def validate_criteria(
        cls,
        value: dict[str, str | None] | list[str],
    ) -> dict[str, str | None] | list[str]:
        labels = list(value) if isinstance(value, dict) else value
        if not 2 <= len(labels) <= 50:
            raise ValueError("choice questions require 2 to 50 criteria")
        if any(not isinstance(label, str) or label.strip() == "" for label in labels):
            raise ValueError("choice labels must be non-empty strings")
        if len(set(labels)) != len(labels):
            raise ValueError("choice labels must be unique")
        return value


class ScoreQuestion(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["score"] = "score"
    instructions: str = Field(min_length=1)
    criteria: list[str]

    @field_validator("criteria")
    @classmethod
    def validate_criteria(cls, value: list[str]) -> list[str]:
        if not 2 <= len(value) <= 50:
            raise ValueError("score questions require 2 to 50 rubric levels")
        if any(item.strip() == "" for item in value):
            raise ValueError("score rubric levels must be non-empty")
        return value


class NoulQuestion(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["noul"] = "noul"
    instructions: str = Field(min_length=1)
    criteria: dict[str, str | None] | None = None

    @field_validator("criteria")
    @classmethod
    def validate_criteria(
        cls,
        value: dict[str, str | None] | None,
    ) -> dict[str, str | None] | None:
        if value is not None and set(value) - {"false", "true"}:
            raise ValueError("noul criteria may only contain false and true")
        return value


Question = Annotated[
    ChoiceQuestion | ScoreQuestion | NoulQuestion,
    Field(discriminator="type"),
]


class ClassifierRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: str = Field(min_length=1)
    state: str | dict[str, Any] | list[Any]
    questions: dict[str, Question]

    @field_validator("questions")
    @classmethod
    def validate_questions(cls, value: dict[str, Question]) -> dict[str, Question]:
        if not 1 <= len(value) <= 256:
            raise ValueError("classifier requests require 1 to 256 questions")
        if any(key.strip() == "" for key in value):
            raise ValueError("question ids must be non-empty")
        return value


class ActionTrace(BaseModel):
    model_config = ConfigDict(extra="forbid")

    act_probability: float = Field(ge=0, le=1)


class ChoiceAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["choice"] = "choice"
    confidence: float = Field(ge=0, le=1)
    action: ActionTrace
    choice: str
    probabilities: dict[str, float]


class ScoreAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["score"] = "score"
    confidence: float = Field(ge=0, le=1)
    action: ActionTrace
    score: float
    legend: dict[str, str]
    probabilities: dict[str, float]


class NoulAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["noul"] = "noul"
    confidence: float = Field(ge=0, le=1)
    action: ActionTrace
    noul: float = Field(ge=0, le=1)


Answer = Annotated[
    ChoiceAnswer | ScoreAnswer | NoulAnswer,
    Field(discriminator="type"),
]


class ClassifierUsage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    input_tokens: int = Field(ge=0)
    output_tokens: Literal[0] = 0


class ClassifierResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: str
    answers: dict[str, Answer]
    usage: ClassifierUsage
    latency_ms: int = Field(ge=0)


class ClassifierErrorResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    message: str
