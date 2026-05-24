from __future__ import annotations

import os
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .protocol import GenerateRequest, ResultResponse, legalize_notes


@asynccontextmanager
async def _lifespan(_: FastAPI):
    broadcaster = None
    try:
        from ..media.bonjour import BonjourServiceBroadcaster

        port = int(os.environ.get("PORT", "8766"))
        broadcaster = BonjourServiceBroadcaster(
            instance_name="LonelyPianist A.I. Duet Server",
            port=port,
            properties={
                b"path": b"/generate",
                b"protocol_version": b"1",
                b"engine": b"magenta",
            },
        )
        await broadcaster.start()
        print(f"[Bonjour] started: type=_lpduet._tcp.local. port={port}")
    except Exception as error:  # noqa: BLE001
        # Best-effort: never break the happy path.
        print(f"[Bonjour] failed to start: {type(error).__name__}: {error!r}")

    try:
        yield
    finally:
        if broadcaster is not None:
            await broadcaster.stop()


app = FastAPI(title="Piano Duet Server", version="0.1.0", lifespan=_lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/generate")
async def generate(request: GenerateRequest) -> ResultResponse:
    from ..engines.placeholder_inference import get_inference_engine

    t0 = time.perf_counter()
    engine = get_inference_engine()
    reply_notes = engine.generate_response(request.notes, request.params, request.session_id)
    reply_notes = legalize_notes(reply_notes)
    latency_ms = int((time.perf_counter() - t0) * 1000)
    return ResultResponse(notes=reply_notes, latency_ms=latency_ms)
