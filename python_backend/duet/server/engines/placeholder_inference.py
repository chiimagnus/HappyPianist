from __future__ import annotations

import random
from dataclasses import dataclass

from ..api.protocol import DialogueNote, GenerateParams, legalize_notes


@dataclass(frozen=True)
class PlaceholderInferenceEngine:
    def generate_response(
        self,
        notes: list[DialogueNote],
        params: GenerateParams,
        session_id: str | None,
    ) -> list[DialogueNote]:
        # A simple, deterministic-ish arpeggio based on the last heard note.
        last_note = 60
        last_velocity = 90
        if notes:
            tail = max(notes, key=lambda item: (item.time + item.duration, item.time))
            last_note = int(tail.note)
            last_velocity = int(tail.velocity)

        rng = random.Random(params.seed if params.seed is not None else 0)
        pattern = [0, 4, 7, 12, 7, 4]
        base = max(36, min(84, last_note))
        velocity = max(0, min(127, max(40, min(110, last_velocity))))

        reply_len_sec = max(2.0, min(12.0, float(params.max_tokens) / 64.0))
        step = 0.18
        dur = 0.16
        count = max(1, int(reply_len_sec / step))

        reply: list[DialogueNote] = []
        for i in range(count):
            pitch = base + pattern[i % len(pattern)] + rng.choice([0, 0, 0, 12])
            reply.append(
                DialogueNote(
                    note=int(pitch),
                    velocity=velocity,
                    time=float(i) * step,
                    duration=dur,
                )
            )

        return legalize_notes(reply)
