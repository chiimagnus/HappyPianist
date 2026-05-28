#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

from pathlib import Path


def _bootstrap_import_path() -> None:
    python_backend_dir = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(python_backend_dir))


_bootstrap_import_path()

from shared.protocol_v2 import (
    ALLOWED_CC_CONTROLLERS,
    ControlChangeEvent,
    GenerateParams,
    GenerateRequestV2,
    NoteEvent,
    ResultResponseV2,
    legalize_events,
)


@dataclass(frozen=True)
class SmokeConfig:
    host: str
    port: int
    timeout_s: float


def parse_args(argv: list[str] | None = None) -> SmokeConfig:
    parser = argparse.ArgumentParser(prog="aria_server_smoketest", add_help=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args(argv)
    return SmokeConfig(host=args.host, port=args.port, timeout_s=args.timeout)


def _post_json(url: str, payload: dict[str, Any], *, timeout_s: float) -> dict[str, Any]:
    data = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    req = urllib.request.Request(url=url, data=data, method="POST")
    req.add_header("Content-Type", "application/json; charset=utf-8")
    req.add_header("Content-Length", str(len(data)))
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        raw = resp.read()
    return json.loads(raw.decode("utf-8"))


def main(argv: list[str] | None = None) -> int:
    config = parse_args(argv)

    request = GenerateRequestV2(
        events=legalize_events(
            [
                ControlChangeEvent(controller=7, value=100, time=0.0),
                ControlChangeEvent(controller=11, value=100, time=0.0),
                ControlChangeEvent(controller=64, value=127, time=0.0),
                NoteEvent(note=60, velocity=96, time=0.0, duration=0.5),
            ]
        ),
        params=GenerateParams(max_tokens=64),
    )
    url = f"http://{config.host}:{config.port}/generate"

    try:
        payload = _post_json(url, request.model_dump(), timeout_s=config.timeout_s)
    except urllib.error.URLError as exc:
        print(f"[smoketest] ERROR: request failed: {exc}", file=sys.stderr, flush=True)
        return 2

    try:
        response = ResultResponseV2.model_validate(payload)
    except Exception as exc:
        print(f"[smoketest] ERROR: invalid response json: {exc}", file=sys.stderr, flush=True)
        return 3

    events = legalize_events(response.events)
    cc_controllers = sorted({e.controller for e in events if isinstance(e, ControlChangeEvent)})
    note_count = sum(1 for e in events if isinstance(e, NoteEvent))
    cc64_count = sum(
        1 for e in events if isinstance(e, ControlChangeEvent) and e.controller == 64
    )

    if note_count < 1:
        print("[smoketest] ERROR: expected at least 1 note event", file=sys.stderr, flush=True)
        return 4
    if cc64_count < 1:
        print("[smoketest] ERROR: expected at least 1 CC64 event", file=sys.stderr, flush=True)
        return 5
    if not set(cc_controllers).issubset(ALLOWED_CC_CONTROLLERS):
        print(
            f"[smoketest] ERROR: unexpected CC controllers: {cc_controllers}",
            file=sys.stderr,
            flush=True,
        )
        return 6

    print(
        f"[smoketest] OK: notes={note_count} cc64={cc64_count} cc_controllers={cc_controllers}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
