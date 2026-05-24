from __future__ import annotations

import random
from dataclasses import dataclass

from api.protocol import DialogueNote, GenerateParams, legalize_notes


@dataclass(frozen=True)
class PlaceholderInferenceEngine:
    def generate_response(
        self,
        notes: list[DialogueNote],
        params: GenerateParams,
        session_id: str | None,
    ) -> list[DialogueNote]:
        # Placeholder mode is meant to be dependency-free, but it should still react to the
        # user's input. The previous implementation always used a fixed arpeggio pattern,
        # which made replies sound like "the same melody" regardless of what the player did.
        #
        # This implementation derives a small interval motif from the prompt notes and
        # continues it deterministically under `params.seed`.
        del session_id

        rng = random.Random(int(params.seed) if params.seed is not None else random.SystemRandom().randint(0, 2**31 - 1))

        # Collect note-on ordering by start time, then derive a motif of pitch intervals.
        ordered = sorted(notes, key=lambda n: (float(n.time), float(n.duration), int(n.note)))
        motif: list[int] = []
        for prev, cur in zip(ordered, ordered[1:]):
            interval = int(cur.note) - int(prev.note)
            if interval == 0:
                continue
            # Clamp extreme leaps for a more piano-friendly continuation.
            motif.append(max(-12, min(12, interval)))
            if len(motif) >= 12:
                break

        # Fallback: choose a basic but not-too-repetitive motif.
        if not motif:
            motif = [2, 2, -1, 2, -2, 3, -2]

        # Base pitch/velocity from the latest note (end time).
        last_note = 60
        last_velocity = 90
        if ordered:
            tail = max(ordered, key=lambda item: (float(item.time) + float(item.duration), float(item.time)))
            last_note = int(tail.note)
            last_velocity = int(tail.velocity)

        velocity = max(40, min(110, last_velocity if last_velocity > 0 else 80))
        base = max(36, min(84, last_note))

        # Reply timing: derive step from the prompt density (keeps it feeling responsive).
        if len(ordered) >= 2:
            spans = [max(0.01, float(b.time) - float(a.time)) for a, b in zip(ordered, ordered[1:])]
            avg_span = sum(spans) / len(spans)
            step = max(0.10, min(0.30, avg_span))
        else:
            step = 0.18
        dur = max(0.08, min(step * 0.9, 0.22))

        reply_len_sec = max(2.0, min(12.0, float(params.max_tokens) / 64.0))
        count = max(1, int(reply_len_sec / step))

        reply: list[DialogueNote] = []
        pitch = base
        for i in range(count):
            interval = motif[i % len(motif)]
            # Occasionally vary direction or add a small chromatic passing tone.
            if rng.random() < 0.12:
                interval = -interval
            if rng.random() < 0.10:
                interval += rng.choice([-1, 1])

            pitch = max(36, min(96, pitch + interval))
            reply.append(
                DialogueNote(
                    note=int(pitch),
                    velocity=int(velocity),
                    time=float(i) * step,
                    duration=float(dur),
                )
            )

        return legalize_notes(reply)
