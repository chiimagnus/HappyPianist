from __future__ import annotations

import json
import os
import random
import string
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import mido


def debug_enabled() -> bool:
    return os.environ.get("DIALOGUE_DEBUG", "").strip() == "1"


def _now_timestamp() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime())


def _random_suffix(length: int = 6) -> str:
    alphabet = string.ascii_lowercase + string.digits
    return "".join(random.choice(alphabet) for _ in range(length))


def new_request_id() -> str:
    # Example: 20260406-174512-3f9k2a
    return time.strftime("%Y%m%d-%H%M%S", time.localtime()) + "-" + _random_suffix()


@dataclass(frozen=True)
class DebugBundlePaths:
    request_dir: Path
    summary_json: Path
    request_json: Path
    response_json: Path
    prompt_midi: Path
    reply_midi: Path
    index_jsonl: Path


def resolve_debug_paths(req_id: str) -> DebugBundlePaths:
    root = Path(__file__).resolve().parents[1] / "out" / "dialogue_debug"
    request_dir = root / "requests" / req_id
    return DebugBundlePaths(
        request_dir=request_dir,
        summary_json=request_dir / "summary.json",
        request_json=request_dir / "request.json",
        response_json=request_dir / "response.json",
        prompt_midi=request_dir / "prompt.mid",
        reply_midi=request_dir / "reply.mid",
        index_jsonl=root / "index.jsonl",
    )


def _write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")


def _append_jsonl(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False))
        f.write("\n")


def _notes_to_midi(notes: list[dict[str, Any]], out_path: Path) -> None:
    midi = mido.MidiFile(ticks_per_beat=480)
    track = mido.MidiTrack()
    midi.tracks.append(track)

    tempo = mido.bpm2tempo(120)
    track.append(mido.MetaMessage("set_tempo", tempo=tempo, time=0))

    events: list[tuple[float, mido.Message]] = []
    for n in notes:
        note = int(n["note"])
        velocity = int(n.get("velocity", 80))
        start = float(n["time"])
        duration = float(n["duration"])
        end = start + max(0.01, duration)

        events.append((start, mido.Message("note_on", note=note, velocity=velocity, channel=0, time=0)))
        events.append((end, mido.Message("note_off", note=note, velocity=0, channel=0, time=0)))

    events.sort(key=lambda x: x[0])

    last_time = 0.0
    for event_time, message in events:
        delta_sec = max(0.0, event_time - last_time)
        delta_ticks = int(round(mido.second2tick(delta_sec, midi.ticks_per_beat, tempo)))
        message.time = delta_ticks
        track.append(message)
        last_time = event_time

    out_path.parent.mkdir(parents=True, exist_ok=True)
    midi.save(str(out_path))


def write_debug_bundle(
    *,
    req_id: str,
    request_payload: dict[str, Any],
    response_payload: dict[str, Any],
    prompt_notes: list[dict[str, Any]],
    reply_notes: list[dict[str, Any]],
    summary: dict[str, Any],
) -> None:
    t0 = time.perf_counter()
    paths = resolve_debug_paths(req_id)

    _write_json(paths.request_json, request_payload)
    _write_json(paths.response_json, response_payload)

    _notes_to_midi(prompt_notes, paths.prompt_midi)
    _notes_to_midi(reply_notes, paths.reply_midi)

    write_debug_ms = int((time.perf_counter() - t0) * 1000)
    if "latency_ms_breakdown" in summary and isinstance(summary["latency_ms_breakdown"], dict):
        summary["latency_ms_breakdown"]["write_debug_files"] = write_debug_ms
    else:
        summary["write_debug_files_ms"] = write_debug_ms

    _write_json(paths.summary_json, summary)

    index_entry = {
        "req_id": req_id,
        "timestamp": summary.get("timestamp") or _now_timestamp(),
        "request_dir": str(paths.request_dir),
        "session_id": summary.get("session_id"),
        "latency_ms_total": summary.get("latency_ms_total"),
        "prompt_note_count": summary.get("prompt_note_count"),
        "reply_note_count": summary.get("reply_note_count"),
    }
    _append_jsonl(paths.index_jsonl, index_entry)
