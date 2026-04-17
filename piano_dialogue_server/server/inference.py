from __future__ import annotations

import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import torch
from transformers import AutoModelForCausalLM

from anticipation.config import TIME_RESOLUTION
from anticipation.vocab import DUR_OFFSET, MAX_PITCH, NOTE_OFFSET, REST, TIME_OFFSET
import anticipation.sample as sample

from .protocol import DialogueNote, GenerateParams


def _ensure_hf_mirror_env() -> None:
    os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")
    os.environ.setdefault("HF_HUB_ETAG_TIMEOUT", "120")
    os.environ.setdefault("HF_HUB_DOWNLOAD_TIMEOUT", "600")


def _resolve_device() -> str:
    explicit = os.environ.get("AMT_DEVICE")
    if explicit:
        return explicit
    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def _resolve_model_ref() -> str:
    explicit_dir = os.environ.get("AMT_MODEL_DIR")
    if explicit_dir:
        return explicit_dir

    default_dir = Path(__file__).resolve().parents[1] / "models" / "music-large-800k"
    if default_dir.exists():
        return str(default_dir)

    return os.environ.get("AMT_MODEL_ID", "stanford-crfm/music-large-800k")


def _patch_safe_logits() -> None:
    old_safe_logits = sample.safe_logits

    def safe_logits_fixed(logits, idx):  # type: ignore[no-untyped-def]
        logits = old_safe_logits(logits, idx)
        if idx % 3 != 2:
            logits[REST] = -float("inf")
        return logits

    sample.safe_logits = safe_logits_fixed  # type: ignore[assignment]

    old_tqdm = sample.tqdm

    def quiet_tqdm(*args, **kwargs):  # type: ignore[no-untyped-def]
        kwargs.setdefault("disable", True)
        return old_tqdm(*args, **kwargs)

    sample.tqdm = quiet_tqdm  # type: ignore[assignment]


def _quantize_seconds(seconds: float) -> int:
    return max(0, int(round(seconds * TIME_RESOLUTION)))


def _notes_to_events(notes: list[DialogueNote], instrument: int = 0) -> list[int]:
    events: list[int] = []
    for note in notes:
        pitch = int(note.note)
        t = _quantize_seconds(float(note.time))
        d = max(1, _quantize_seconds(float(note.duration)))
        note_id = instrument * MAX_PITCH + pitch
        events.extend([TIME_OFFSET + t, DUR_OFFSET + d, NOTE_OFFSET + note_id])
    return events


def _events_to_notes(
    events: list[int],
    *,
    start_time_sec: float,
    default_velocity: int,
    stats: dict[str, int] | None = None,
) -> list[DialogueNote]:
    notes: list[DialogueNote] = []
    if len(events) < 3:
        if stats is not None:
            stats["events_too_short"] = int(stats.get("events_too_short", 0)) + 1
        return notes

    def inc(reason: str) -> None:
        if stats is None:
            return
        stats[reason] = int(stats.get(reason, 0)) + 1

    for i in range(0, len(events) - 2, 3):
        t_token, d_token, n_token = events[i : i + 3]
        if not (t_token >= TIME_OFFSET and d_token >= DUR_OFFSET and n_token >= NOTE_OFFSET):
            inc("invalid_triplet")
            continue

        t_ticks = t_token - TIME_OFFSET
        d_ticks = d_token - DUR_OFFSET
        note_id = n_token - NOTE_OFFSET

        instrument = note_id // MAX_PITCH
        pitch = note_id - instrument * MAX_PITCH
        if instrument != 0:
            inc("instrument_not_piano")
            continue
        if pitch < 21 or pitch > 108:
            inc("pitch_out_of_range")
            continue

        time_sec = t_ticks / TIME_RESOLUTION - start_time_sec
        duration_sec = max(0.01, d_ticks / TIME_RESOLUTION)
        if time_sec < 0:
            inc("negative_time")
            continue

        notes.append(
            DialogueNote(note=pitch, velocity=default_velocity, time=time_sec, duration=duration_sec)
        )

    if stats is not None:
        stats["emitted_notes"] = len(notes)
    return notes


def _max_phrase_end_sec(notes: list[DialogueNote]) -> float:
    if not notes:
        return 0.0
    return max(float(note.time + note.duration) for note in notes)


def _derive_response_length_sec(params: GenerateParams) -> float:
    # Heuristic mapping: anticipation.generate is time-window based, but the protocol uses max_tokens.
    # Map "tokens" to a short response window that is stable by default.
    sec = params.max_tokens / 64.0
    return max(2.0, min(sec, 12.0))


@dataclass(frozen=True)
class InferenceEngine:
    model_ref: str
    device: str
    model: Any
    load_ms: int

    def generate_response(
        self, notes: list[DialogueNote], params: GenerateParams, session_id: str | None
    ) -> list[DialogueNote]:
        del session_id

        prompt_end_sec = _max_phrase_end_sec(notes)
        start_time_sec = max(0.0, prompt_end_sec)
        end_time_sec = start_time_sec + _derive_response_length_sec(params)

        prompt_events = _notes_to_events(notes, instrument=0)
        events = sample.generate(
            self.model,
            start_time=start_time_sec,
            end_time=end_time_sec,
            inputs=prompt_events,
            top_p=params.top_p,
        )

        if notes:
            default_velocity = int(sum(n.velocity for n in notes) / len(notes))
            default_velocity = max(1, min(default_velocity, 127))
        else:
            default_velocity = 80

        return _events_to_notes(events, start_time_sec=start_time_sec, default_velocity=default_velocity)

    def generate_response_with_debug(
        self, notes: list[DialogueNote], params: GenerateParams, session_id: str | None
    ) -> tuple[list[DialogueNote], dict[str, Any]]:
        del session_id

        prompt_end_sec = _max_phrase_end_sec(notes)
        start_time_sec = max(0.0, prompt_end_sec)
        response_length_sec = _derive_response_length_sec(params)
        end_time_sec = start_time_sec + response_length_sec

        prompt_events = _notes_to_events(notes, instrument=0)
        t0 = time.perf_counter()
        events = sample.generate(
            self.model,
            start_time=start_time_sec,
            end_time=end_time_sec,
            inputs=prompt_events,
            top_p=params.top_p,
        )
        generate_ms = int((time.perf_counter() - t0) * 1000)

        if notes:
            default_velocity = int(sum(n.velocity for n in notes) / len(notes))
            default_velocity = max(1, min(default_velocity, 127))
        else:
            default_velocity = 80

        dropped: dict[str, int] = {}
        reply_notes = _events_to_notes(
            events, start_time_sec=start_time_sec, default_velocity=default_velocity, stats=dropped
        )

        debug: dict[str, Any] = {
            "prompt_end_sec": prompt_end_sec,
            "effective_start_sec": start_time_sec,
            "effective_end_sec": end_time_sec,
            "effective_response_length_sec": response_length_sec,
            "prompt_events_len": len(prompt_events),
            "generated_events_len": len(events),
            "default_velocity": default_velocity,
            "dropped_notes": dropped,
            "generate_ms": generate_ms,
        }
        return reply_notes, debug


_engine: InferenceEngine | None = None


def get_inference_engine() -> InferenceEngine:
    global _engine
    if _engine is not None:
        return _engine

    _ensure_hf_mirror_env()
    _patch_safe_logits()

    model_ref = _resolve_model_ref()
    device = _resolve_device()

    if Path(model_ref).is_dir():
        model_path = Path(model_ref)
        has_weights = any(model_path.glob("*.safetensors")) or any(model_path.glob("pytorch_model*.bin"))
        if not has_weights:
            raise RuntimeError(f"Model directory exists but weights not found: {model_ref}")

    t0 = time.time()
    model = AutoModelForCausalLM.from_pretrained(model_ref)
    model.to(device)
    model.eval()
    load_ms = int((time.time() - t0) * 1000)

    _engine = InferenceEngine(model_ref=model_ref, device=device, model=model, load_ms=load_ms)
    return _engine
