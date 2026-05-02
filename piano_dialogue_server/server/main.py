from __future__ import annotations

import base64
from contextlib import asynccontextmanager
import json
import os
import tempfile
import time
from typing import Any

from pathlib import Path

from fastapi import FastAPI, File, Form, UploadFile, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import ValidationError
from starlette.websockets import WebSocketDisconnect

from .debug_artifacts import debug_enabled, new_request_id, write_debug_bundle
from .midi_generation import (
    NoteEvent,
    _generate_accompaniment,
    _quantize_to_scale,
    _scale_notes,
    generate_expanded_midi,
    parse_midi_file,
    summarize_analysis,
    write_midi,
)
from .protocol import DialogueNote, ErrorResponse, GenerateParams, GenerateRequest, ResultResponse


@asynccontextmanager
async def _lifespan(_: FastAPI):
    broadcaster = None
    try:
        from .bonjour import BonjourServiceBroadcaster

        broadcaster = BonjourServiceBroadcaster(
            instance_name="LonelyPianist Dialogue Server",
            port=8765,
            properties={
                b"path": b"/generate",
                b"protocol_version": b"1",
                b"supports_deterministic": b"1",
            },
        )
        await broadcaster.start()
    except Exception as error:  # noqa: BLE001
        # Best-effort: never break the happy path.
        print(f"[Bonjour] failed to start: {type(error).__name__}: {error!r}")

    try:
        yield
    finally:
        if broadcaster is not None:
            await broadcaster.stop()


app = FastAPI(title="Piano Dialogue Server", version="0.1.0", lifespan=_lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# Serve static frontend files
_static_dir = Path(__file__).resolve().parents[1] / "static"
if _static_dir.exists():
    app.mount("/static", StaticFiles(directory=str(_static_dir)), name="static")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/", response_class=HTMLResponse)
async def index() -> str:
    index_path = _static_dir / "index.html"
    if index_path.exists():
        return index_path.read_text(encoding="utf-8")
    return "<h1>Piano Dialogue Server</h1><p>Frontend not found. Place static/index.html to serve UI.</p>"


def _quantize_notes_to_scale(notes: list[NoteEvent], key_root: int, key_mode: str) -> list[NoteEvent]:
    """Snap generated notes to the key scale to improve harmony."""
    scale = _scale_notes(key_root, key_mode)
    return [
        NoteEvent(
            note=_quantize_to_scale(n.note, scale, key_root),
            velocity=n.velocity,
            start=n.start,
            duration=n.duration,
            channel=n.channel,
            track=n.track,
        )
        for n in notes
    ]


def _quantize_timing(notes: list[NoteEvent], tempo_bpm: float, time_sig: tuple[int, int]) -> list[NoteEvent]:
    """Align note starts to the beat grid for rhythmic consistency."""
    if not notes:
        return notes

    beat_duration = 60.0 / tempo_bpm
    grid = beat_duration / 8.0  # 1/8 beat grid

    # Quantize the first note and shift all by the same offset to preserve intervals
    first = notes[0]
    offset = round(first.start / grid) * grid - first.start

    return [
        NoteEvent(
            note=n.note,
            velocity=n.velocity,
            start=max(0.0, n.start + offset),
            duration=n.duration,
            channel=n.channel,
            track=n.track,
        )
        for n in notes
    ]


@app.post("/upload-expand")
async def upload_expand(
    file: UploadFile = File(...),
    strategy: str = Form("algorithm"),
    mode: str = Form("variation"),
    extra_duration: float = Form(20.0),
    include_source: bool = Form(False),
    seed: int | None = Form(None),
    top_p: float = Form(0.95),
) -> JSONResponse:
    suffix = Path(file.filename or "input.mid").suffix
    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = Path(tmpdir) / f"input{suffix}"
        output_path = Path(tmpdir) / f"generated{suffix}"

        # Save uploaded file
        content = await file.read()
        input_path.write_bytes(content)

        # Validate MIDI header
        if len(content) < 4 or content[:4] != b'MThd':
            return JSONResponse(
                {"error": "上传的文件不是有效的 MIDI 文件，请检查文件格式"},
                status_code=400,
            )

        # Parse
        try:
            source_notes, analysis = parse_midi_file(input_path)
        except OSError as e:
            return JSONResponse(
                {"error": f"无法解析 MIDI 文件: {str(e)}"},
                status_code=400,
            )

        if strategy == "model":
            from .inference import (
                _dialogue_notes_to_note_events,
                _note_events_to_dialogue_notes,
                get_inference_engine,
            )

            # Convert source notes to DialogueNote for the model
            dialogue_notes = _note_events_to_dialogue_notes(source_notes)

            # Map extra_duration to max_tokens (~64 tokens per second)
            max_tokens = int(extra_duration * 64)
            max_tokens = max(64, min(max_tokens, 2048))

            params = GenerateParams(top_p=top_p, max_tokens=max_tokens, strategy="model")
            engine = get_inference_engine()
            response_notes = engine.generate_response(dialogue_notes, params, session_id=None)

            # Convert model response back to NoteEvent and shift times after source
            prompt_end_sec = (
                max(note.start + note.duration for note in source_notes) if source_notes else 0.0
            )
            continuation = _dialogue_notes_to_note_events(response_notes)
            adjusted_continuation = [
                NoteEvent(
                    note=n.note,
                    velocity=n.velocity,
                    start=n.start + prompt_end_sec,
                    duration=n.duration,
                    channel=0,
                    track=0,
                )
                for n in continuation
            ]

            # Tuning: snap to scale and quantize timing
            adjusted_continuation = _quantize_notes_to_scale(
                adjusted_continuation, analysis.key_root, analysis.key_mode
            )
            adjusted_continuation = _quantize_timing(
                adjusted_continuation, analysis.tempo_bpm, analysis.time_signature
            )

            if include_source:
                melody = list(source_notes) + adjusted_continuation
            else:
                melody = adjusted_continuation

            accompaniment = _generate_accompaniment(melody, analysis, bar_length=4.0)
        else:
            # Algorithm-based generation
            melody, accompaniment = generate_expanded_midi(
                source_notes,
                analysis,
                mode=mode,
                extra_duration=extra_duration,
                include_source=include_source,
                seed=seed,
            )

        write_midi(melody, accompaniment, analysis, output_path)

        # Read generated MIDI as base64 for frontend download
        midi_bytes = output_path.read_bytes()
        midi_base64 = base64.b64encode(midi_bytes).decode("ascii")

        return JSONResponse(
            {
                "analysis": summarize_analysis(analysis),
                "source_note_count": len(source_notes),
                "generated_melody_count": len(melody) - (len(source_notes) if include_source else 0),
                "generated_accompaniment_count": len(accompaniment),
                "strategy": strategy,
                "mode": mode,
                "extra_duration": extra_duration,
                "filename": f"{Path(file.filename or 'output').stem}_generated.mid",
                "midi_base64": midi_base64,
            }
        )


def _handle_generate_request(request: GenerateRequest) -> ResultResponse:
    from .inference import generate_deterministic_response, get_inference_engine

    if request.params.strategy == "deterministic":
        reply_notes = generate_deterministic_response(request.notes, request.params, request.session_id)
        return ResultResponse(notes=reply_notes, latency_ms=None)

    engine = get_inference_engine()
    reply_notes = engine.generate_response(request.notes, request.params, request.session_id)
    return ResultResponse(notes=reply_notes, latency_ms=None)


@app.post("/generate")
async def generate(request: GenerateRequest) -> ResultResponse:
    return _handle_generate_request(request)


@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket) -> None:
    from .inference import generate_deterministic_response, get_inference_engine

    await websocket.accept()
    try:
        while True:
            debug_on = debug_enabled()
            req_id = new_request_id() if debug_on else None
            t_total0 = time.perf_counter()
            t_parse0 = t_total0
            raw = await websocket.receive_text()
            try:
                payload: Any = json.loads(raw)
            except Exception:
                await websocket.send_json(ErrorResponse(message="invalid json").model_dump())
                continue
            t_parse_ms = int((time.perf_counter() - t_parse0) * 1000)

            if not isinstance(payload, dict):
                await websocket.send_json(ErrorResponse(message="invalid payload").model_dump())
                continue

            message_type = payload.get("type")
            if message_type != "generate":
                await websocket.send_json(
                    ErrorResponse(message=f"unsupported type: {message_type!r}").model_dump()
                )
                continue

            try:
                t_validate0 = time.perf_counter()
                request = GenerateRequest.model_validate(payload)
                t_validate_ms = int((time.perf_counter() - t_validate0) * 1000)
            except ValidationError as error:
                await websocket.send_json(ErrorResponse(message=str(error)).model_dump())
                continue

            try:
                engine = None
                t_engine_ms = 0
                if request.params.strategy != "deterministic":
                    t_engine0 = time.perf_counter()
                    engine = get_inference_engine()
                    t_engine_ms = int((time.perf_counter() - t_engine0) * 1000)

                t_generate0 = time.perf_counter()
                inference_debug: dict[str, Any] | None = None
                if request.params.strategy == "deterministic":
                    reply_notes = generate_deterministic_response(
                        request.notes, request.params, request.session_id
                    )
                elif debug_on:
                    assert engine is not None
                    reply_notes, inference_debug = engine.generate_response_with_debug(
                        request.notes, request.params, request.session_id
                    )
                else:
                    assert engine is not None
                    reply_notes = engine.generate_response(request.notes, request.params, request.session_id)
                t_generate_ms = int((time.perf_counter() - t_generate0) * 1000)

                latency_ms = int((time.perf_counter() - t_total0) * 1000)
                response = ResultResponse(notes=reply_notes, latency_ms=latency_ms)
                response_payload = response.model_dump()
                t_serialize0 = time.perf_counter()
                await websocket.send_json(response_payload)
                t_serialize_ms = int((time.perf_counter() - t_serialize0) * 1000)

                if req_id is not None:
                    try:
                        def span(notes: list[dict[str, Any]]) -> dict[str, float]:
                            if not notes:
                                return {"start": 0.0, "end": 0.0, "duration": 0.0}
                            start = min(float(n["time"]) for n in notes)
                            end = max(float(n["time"]) + float(n["duration"]) for n in notes)
                            return {"start": start, "end": end, "duration": max(0.0, end - start)}

                        prompt_notes = [note.model_dump() for note in request.notes]
                        reply_notes_dump = [note.model_dump() for note in reply_notes]

                        client_host = None
                        if websocket.client is not None:
                            client_host = f"{websocket.client.host}:{websocket.client.port}"

                        torch_version = None
                        transformers_version = None
                        try:
                            import torch  # type: ignore
                            import transformers  # type: ignore

                            torch_version = getattr(torch, "__version__", None)
                            transformers_version = getattr(transformers, "__version__", None)
                        except Exception:
                            pass

                        summary: dict[str, Any] = {
                            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime()),
                            "req_id": req_id,
                            "session_id": request.session_id,
                            "client": client_host,
                            "model_ref": engine.model_ref if engine is not None else None,
                            "device": engine.device if engine is not None else None,
                            "torch_version": torch_version,
                            "transformers_version": transformers_version,
                            "engine_load_ms": engine.load_ms if engine is not None else None,
                            "protocol_version": request.protocol_version,
                            "params": request.params.model_dump(),
                            "prompt_note_count": len(prompt_notes),
                            "reply_note_count": len(reply_notes_dump),
                            "prompt_span_sec": span(prompt_notes),
                            "reply_span_sec": span(reply_notes_dump),
                            "latency_ms_total": latency_ms,
                            "latency_ms_breakdown": {
                                "parse": t_parse_ms,
                                "validate": t_validate_ms,
                                "engine_get": t_engine_ms,
                                "generate": t_generate_ms,
                                "send_json": t_serialize_ms,
                            },
                        }
                        if inference_debug is not None:
                            summary.update(inference_debug)

                        write_debug_bundle(
                            req_id=req_id,
                            request_payload=payload,
                            response_payload=response_payload,
                            prompt_notes=prompt_notes,
                            reply_notes=reply_notes_dump,
                            summary=summary,
                        )
                    except Exception as error:  # noqa: BLE001
                        # Best-effort: never break the happy path.
                        print(f"[DialogueDebug] failed to write debug bundle: {error}")
            except Exception as error:  # noqa: BLE001
                await websocket.send_json(ErrorResponse(message=str(error)).model_dump())
    except WebSocketDisconnect:
        return
