from __future__ import annotations

import argparse
import asyncio
import json

import websockets


async def _run(uri: str) -> int:
    payload = {
        "type": "generate",
        "protocol_version": 1,
        "notes": [
            {"note": 60, "velocity": 90, "time": 0.0, "duration": 0.25},
            {"note": 64, "velocity": 90, "time": 0.25, "duration": 0.25},
            {"note": 67, "velocity": 90, "time": 0.5, "duration": 0.25},
        ],
        "params": {
            "top_p": 0.95,
            "max_tokens": 128,
            "strategy": "model",
        },
    }

    async with websockets.connect(uri, open_timeout=5) as ws:
        await ws.send(json.dumps(payload, ensure_ascii=False))
        raw = await ws.recv()
        print(raw)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="WebSocket smoke test for piano_dialogue_server.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    uri = f"ws://{args.host}:{args.port}/ws"
    return asyncio.run(_run(uri))


if __name__ == "__main__":
    raise SystemExit(main())

