from __future__ import annotations

import json
from typing import Any

from fastapi import FastAPI, WebSocket

app = FastAPI(title="Piano Dialogue Server", version="0.1.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        while True:
            raw = await websocket.receive_text()
            try:
                payload: Any = json.loads(raw)
            except Exception:
                payload = {"type": "error", "message": "invalid json"}
            await websocket.send_json(payload)
    finally:
        await websocket.close()

