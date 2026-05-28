from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from shared.protocol_v2 import ImprovEvent, GenerateRequestV2, legalize_events


class StreamStartRequestV2(BaseModel):
    model_config = ConfigDict(extra="ignore")

    type: str = "start"
    protocol_version: Literal[2] = 2
    request: GenerateRequestV2


class StreamTimeRange(BaseModel):
    model_config = ConfigDict(extra="ignore")

    start: float = Field(ge=0)
    end: float = Field(ge=0)


class StreamChunkV2(BaseModel):
    model_config = ConfigDict(extra="ignore")

    type: str = "chunk"
    protocol_version: Literal[2] = 2
    seq: int = Field(ge=0)
    is_final: bool = False
    time_range: StreamTimeRange
    events: list[ImprovEvent]
    latency_ms: int | None = None

    def legalized(self) -> "StreamChunkV2":
        return StreamChunkV2(
            seq=self.seq,
            is_final=self.is_final,
            time_range=self.time_range,
            events=legalize_events(self.events),
            latency_ms=self.latency_ms,
        )
