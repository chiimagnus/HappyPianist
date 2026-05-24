from __future__ import annotations

import json
import os
import random
import string
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


def debug_enabled(env_key: str) -> bool:
    return os.environ.get(env_key, "").strip() == "1"


def now_timestamp() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime())


def random_suffix(length: int = 6) -> str:
    alphabet = string.ascii_lowercase + string.digits
    return "".join(random.choice(alphabet) for _ in range(length))


def new_request_id() -> str:
    # Example: 20260524-115233-3f9k2a
    return time.strftime("%Y%m%d-%H%M%S", time.localtime()) + "-" + random_suffix()


@dataclass(frozen=True)
class DebugBundlePaths:
    request_dir: Path
    summary_json: Path
    request_json: Path
    response_json: Path
    prompt_notes_json: Path
    reply_notes_json: Path
    index_jsonl: Path


def resolve_debug_paths(service_root: Path, req_id: str) -> DebugBundlePaths:
    root = service_root / "out" / "debug"
    request_dir = root / "requests" / req_id
    return DebugBundlePaths(
        request_dir=request_dir,
        summary_json=request_dir / "summary.json",
        request_json=request_dir / "request.json",
        response_json=request_dir / "response.json",
        prompt_notes_json=request_dir / "prompt_notes.json",
        reply_notes_json=request_dir / "reply_notes.json",
        index_jsonl=root / "index.jsonl",
    )


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")


def append_jsonl(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False))
        f.write("\n")


def write_debug_bundle(
    *,
    service_root: Path,
    req_id: str,
    request_payload: dict[str, Any],
    response_payload: dict[str, Any],
    prompt_notes: list[dict[str, Any]],
    reply_notes: list[dict[str, Any]],
    summary: dict[str, Any],
) -> None:
    t0 = time.perf_counter()
    paths = resolve_debug_paths(service_root, req_id)

    write_json(paths.request_json, request_payload)
    write_json(paths.response_json, response_payload)
    write_json(paths.prompt_notes_json, prompt_notes)
    write_json(paths.reply_notes_json, reply_notes)

    write_debug_ms = int((time.perf_counter() - t0) * 1000)
    summary["write_debug_files_ms"] = write_debug_ms
    summary.setdefault("timestamp", now_timestamp())
    write_json(paths.summary_json, summary)

    index_entry = {
        "req_id": req_id,
        "timestamp": summary.get("timestamp") or now_timestamp(),
        "request_dir": str(paths.request_dir),
        "session_id": summary.get("session_id"),
        "engine": summary.get("engine"),
        "model_ref": summary.get("model_ref"),
        "latency_ms_total": summary.get("latency_ms_total"),
        "prompt_note_count": summary.get("prompt_note_count"),
        "reply_note_count": summary.get("reply_note_count"),
    }
    append_jsonl(paths.index_jsonl, index_entry)

