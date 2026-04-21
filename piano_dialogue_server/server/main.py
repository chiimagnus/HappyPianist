from __future__ import annotations

import json
import time
from typing import Any

from fastapi import FastAPI, WebSocket
from pydantic import ValidationError
from starlette.websockets import WebSocketDisconnect

from .debug_artifacts import debug_enabled, new_request_id, write_debug_bundle
from .inference import get_inference_engine
from .protocol import ErrorResponse, GenerateRequest, ResultResponse

app = FastAPI(title="Piano Dialogue Server", version="0.1.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket) -> None:
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
                t_engine0 = time.perf_counter()
                engine = get_inference_engine()
                t_engine_ms = int((time.perf_counter() - t_engine0) * 1000)

                t_generate0 = time.perf_counter()
                inference_debug: dict[str, Any] | None = None
                if debug_on:
                    reply_notes, inference_debug = engine.generate_response_with_debug(
                        request.notes, request.params, request.session_id
                    )
                else:
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
                            "model_ref": engine.model_ref,
                            "device": engine.device,
                            "torch_version": torch_version,
                            "transformers_version": transformers_version,
                            "engine_load_ms": engine.load_ms,
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
