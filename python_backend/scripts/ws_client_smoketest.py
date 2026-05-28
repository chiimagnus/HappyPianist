#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import sys
from dataclasses import dataclass
from pathlib import Path

from aiohttp import ClientSession, ClientTimeout, WSMsgType


def _bootstrap_import_path() -> None:
    python_backend_dir = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(python_backend_dir))


_bootstrap_import_path()

from shared.protocol_v2 import ControlChangeEvent, GenerateParams, GenerateRequestV2, NoteEvent, legalize_events  # noqa: E402
from shared.streaming_protocol_v2 import StreamChunkV2, StreamStartRequestV2  # noqa: E402


@dataclass(frozen=True)
class Config:
    url: str
    timeout_s: float


def parse_args(argv: list[str] | None = None) -> Config:
    parser = argparse.ArgumentParser(prog="ws_client_smoketest", add_help=True)
    parser.add_argument("url", help="e.g. ws://127.0.0.1:8766/stream")
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args(argv)
    return Config(url=args.url, timeout_s=args.timeout)


async def main_async(argv: list[str] | None = None) -> int:
    config = parse_args(argv)

    start = StreamStartRequestV2(
        request=GenerateRequestV2(
            events=legalize_events(
                [
                    ControlChangeEvent(controller=7, value=100, time=0.0),
                    ControlChangeEvent(controller=11, value=100, time=0.0),
                    ControlChangeEvent(controller=64, value=127, time=0.0),
                    NoteEvent(note=60, velocity=96, time=0.0, duration=0.5),
                ]
            ),
            params=GenerateParams(max_tokens=128),
        )
    )

    last_seq = -1
    last_end = 0.0
    got_final = False
    chunk_count = 0

    async with ClientSession(timeout=ClientTimeout(total=config.timeout_s)) as session:
        async with session.ws_connect(config.url) as ws:
            await ws.send_json(start.model_dump())

            async for msg in ws:
                if msg.type == WSMsgType.TEXT:
                    chunk = StreamChunkV2.model_validate_json(msg.data)
                    chunk_count += 1
                    if chunk.seq <= last_seq:
                        print(f"[ws_smoketest] ERROR: non-monotonic seq: {chunk.seq} after {last_seq}", file=sys.stderr)
                        return 2
                    if chunk.time_range.start < last_end - 1e-9:
                        print(
                            f"[ws_smoketest] ERROR: overlapping time_range: {chunk.time_range.start} < {last_end}",
                            file=sys.stderr,
                        )
                        return 3

                    last_seq = chunk.seq
                    last_end = max(last_end, chunk.time_range.end)
                    got_final = got_final or chunk.is_final

                    if chunk.is_final:
                        break
                elif msg.type in (WSMsgType.CLOSE, WSMsgType.CLOSED):
                    break
                elif msg.type == WSMsgType.ERROR:
                    print(f"[ws_smoketest] ERROR: ws error: {ws.exception()}", file=sys.stderr)
                    return 4

    if not got_final:
        print("[ws_smoketest] ERROR: missing final chunk", file=sys.stderr)
        return 5

    print(f"[ws_smoketest] OK: chunks={chunk_count} last_seq={last_seq} last_end={last_end:.3f}s", flush=True)
    return 0


def main(argv: list[str] | None = None) -> int:
    return asyncio.run(main_async(argv))


if __name__ == "__main__":
    raise SystemExit(main())
