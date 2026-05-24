from __future__ import annotations

import os
import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .protocol import GenerateRequest, ResultResponse, legalize_notes
from service_profile import DEBUG_ENV_KEY, DEFAULT_PORT, INSTANCE_NAME, SERVICE_TYPE, TXT_RECORD


@asynccontextmanager
async def _lifespan(_: FastAPI):
    broadcaster = None
    engine = None
    engine_impl = None
    try:
        from engines.inference_engine import get_inference_engine

        engine = get_inference_engine()
        engine_impl = type(engine).__name__
        print(f"[DuetEngine] ready: {engine_impl}")
    except Exception as error:  # noqa: BLE001
        # Best-effort: keep server alive even if model init fails.
        print(f"[DuetEngine] failed to init: {type(error).__name__}: {error!r}")

    try:
        from python_backend.shared.bonjour import BonjourServiceBroadcaster

        port = int(os.environ.get("PORT", str(DEFAULT_PORT)))
        properties: dict[bytes, bytes] = dict(TXT_RECORD)
        engine_name = os.environ.get("DUET_ENGINE", "placeholder").strip().lower()
        if engine_name in ("placeholder", "stub", "auto"):
            engine_name = "placeholder"
        properties[b"engine"] = engine_name.encode("utf-8")
        if engine_impl:
            properties[b"engine_impl"] = engine_impl.encode("utf-8")

        broadcaster = BonjourServiceBroadcaster(
            service_type=SERVICE_TYPE,
            instance_name=INSTANCE_NAME,
            port=port,
            properties=properties,
        )
        await broadcaster.start()
        print(f"[Bonjour] started: type={SERVICE_TYPE} port={port} engine_impl={engine_impl or 'unknown'}")
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
    from engines.inference_engine import get_inference_engine

    t0 = time.perf_counter()
    engine = get_inference_engine()
    reply_notes = engine.generate_response(request.notes, request.params, request.session_id)
    reply_notes = legalize_notes(reply_notes)
    latency_ms = int((time.perf_counter() - t0) * 1000)
    response = ResultResponse(notes=reply_notes, latency_ms=latency_ms)

    try:
        from python_backend.shared.debug_artifacts import debug_enabled, new_request_id, write_debug_bundle

        if debug_enabled(DEBUG_ENV_KEY):
            req_id = new_request_id()
            service_root = Path(__file__).resolve().parents[2]

            def span(notes_dump: list[dict]) -> dict[str, float]:
                if not notes_dump:
                    return {"start": 0.0, "end": 0.0, "duration": 0.0}
                start = min(float(n.get("time", 0.0)) for n in notes_dump)
                end = max(float(n.get("time", 0.0)) + float(n.get("duration", 0.0)) for n in notes_dump)
                return {"start": start, "end": end, "duration": max(0.0, end - start)}

            prompt_notes = [note.model_dump() for note in request.notes]
            reply_notes_dump = [note.model_dump() for note in reply_notes]

            model_ref = None
            if hasattr(engine, "model_name"):
                try:
                    model_ref = str(getattr(engine, "model_name"))
                except Exception:
                    model_ref = None

            summary = {
                "req_id": req_id,
                "session_id": request.session_id,
                "engine": type(engine).__name__,
                "model_ref": model_ref,
                "protocol_version": request.protocol_version,
                "params": request.params.model_dump(),
                "prompt_note_count": len(prompt_notes),
                "reply_note_count": len(reply_notes_dump),
                "prompt_span_sec": span(prompt_notes),
                "reply_span_sec": span(reply_notes_dump),
                "latency_ms_total": latency_ms,
            }

            write_debug_bundle(
                service_root=service_root,
                req_id=req_id,
                request_payload=request.model_dump(),
                response_payload=response.model_dump(),
                prompt_notes=prompt_notes,
                reply_notes=reply_notes_dump,
                summary=summary,
            )
    except Exception as error:  # noqa: BLE001
        # Best-effort: never break the happy path.
        print(f"[DuetDebug] failed to write debug bundle: {type(error).__name__}: {error!r}")

    return response
