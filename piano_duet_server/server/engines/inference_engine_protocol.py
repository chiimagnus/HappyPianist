from __future__ import annotations

from typing import Protocol

from ..api.protocol import DialogueNote, GenerateParams


class InferenceEngineProtocol(Protocol):
    def generate_response(
        self,
        notes: list[DialogueNote],
        params: GenerateParams,
        session_id: str | None,
    ) -> list[DialogueNote]: ...
