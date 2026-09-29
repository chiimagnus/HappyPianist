from __future__ import annotations

import argparse
import asyncio
import logging
import threading
import time
from dataclasses import dataclass
from typing import Any

from aiohttp import web

from shared.companion_semantics import (
    action_from_semantics,
    aggregate_semantics,
    build_semantic_prompt,
    semantic_question_ids,
)
from shared.qwen_companion_protocol import (
    COMPANION_DECISION_PATH,
    ENGINE_ID,
    MODEL_ID,
    PROTOCOL_VERSION,
    CompanionDecisionRequest,
    CompanionDecisionResponse,
    CompanionErrorResponse,
    CompanionUsage,
    SemanticValues,
)

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ServerConfig:
    host: str
    port: int


def parse_args(argv: list[str] | None = None) -> ServerConfig:
    parser = argparse.ArgumentParser(prog="qwen_server", add_help=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8767)
    args = parser.parse_args(argv)
    return ServerConfig(host=str(args.host), port=int(args.port))


@dataclass(frozen=True)
class CompiledQuestion:
    question_id: str
    token_ids: list[int]
    candidate_ids: list[int]


class TransformersQwenRuntime:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._tokenizer: Any | None = None
        self._model: Any | None = None

    def load(self) -> None:
        with self._lock:
            if self._model is not None:
                return

            import torch
            from transformers import AutoModelForCausalLM, AutoTokenizer

            if torch.cuda.is_available() is False:
                raise RuntimeError("Qwen companion service requires CUDA")

            tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
            model = AutoModelForCausalLM.from_pretrained(
                MODEL_ID,
                dtype=torch.bfloat16,
            )
            model.eval().to("cuda")

            self._tokenizer = tokenizer
            self._model = model
            logger.info("Qwen companion runtime loaded: model=%s device=cuda", MODEL_ID)

    def _render_plan(self, question_id: str, state: dict[str, Any]) -> tuple[list[int], list[int]]:
        if self._tokenizer is None:
            raise RuntimeError("Qwen runtime is not loaded")

        plan = build_semantic_prompt(state, question_id)
        rendered = (
            self._tokenizer.apply_chat_template(
                plan.messages,
                tokenize=False,
                add_generation_prompt=True,
                enable_thinking=False,
            )
            + plan.answer_prefix
        )
        token_ids = self._tokenizer.encode(rendered, add_special_tokens=False)
        candidate_ids: list[int] = []
        for candidate in plan.labels:
            extended = self._tokenizer.encode(
                rendered + candidate,
                add_special_tokens=False,
            )
            if (
                len(extended) != len(token_ids) + 1
                or extended[: len(token_ids)] != token_ids
            ):
                return token_ids, []
            candidate_ids.append(int(extended[-1]))
        if len(set(candidate_ids)) != 2:
            return token_ids, []
        return token_ids, candidate_ids

    def _compile_question(
        self,
        state: dict[str, Any],
        question_id: str,
    ) -> CompiledQuestion:
        token_ids, candidate_ids = self._render_plan(question_id, state)
        if not candidate_ids:
            raise RuntimeError(
                f"binary labels for {question_id!r} are not single-token stable"
            )
        return CompiledQuestion(
            question_id=question_id,
            token_ids=token_ids,
            candidate_ids=candidate_ids,
        )

    def _forward_full(
        self,
        compiled: list[CompiledQuestion],
        torch: Any,
        pad_token_id: int,
    ) -> list[Any]:
        max_length = max(len(item.token_ids) for item in compiled)
        input_ids = torch.full(
            (len(compiled), max_length),
            pad_token_id,
            dtype=torch.long,
            device="cuda",
        )
        attention_mask = torch.zeros(
            (len(compiled), max_length),
            dtype=torch.long,
            device="cuda",
        )
        for row, item in enumerate(compiled):
            length = len(item.token_ids)
            input_ids[row, :length] = torch.tensor(
                item.token_ids,
                dtype=torch.long,
                device="cuda",
            )
            attention_mask[row, :length] = 1

        output = self._model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            use_cache=False,
        ).logits
        return [
            output[row, len(item.token_ids) - 1]
            for row, item in enumerate(compiled)
        ]

    def decide(
        self,
        request: CompanionDecisionRequest,
        *,
        server_started: float,
    ) -> CompanionDecisionResponse:
        with self._lock:
            if self._model is None or self._tokenizer is None:
                raise RuntimeError("Qwen runtime is not loaded")

            import torch

            state = request.state.model_dump()
            compiled = [
                self._compile_question(state, question_id)
                for question_id in semantic_question_ids()
            ]
            pad_token_id = self._tokenizer.pad_token_id
            if pad_token_id is None:
                pad_token_id = self._tokenizer.eos_token_id
            if pad_token_id is None:
                raise RuntimeError("tokenizer has no pad or eos token")

            with torch.inference_mode():
                last_logits = self._forward_full(
                    compiled,
                    torch,
                    int(pad_token_id),
                )

            question_probabilities: dict[str, dict[str, float]] = {}
            for item, logits in zip(compiled, last_logits):
                selected_ids = torch.tensor(item.candidate_ids, device=logits.device)
                values = (
                    torch.softmax(
                        logits.index_select(0, selected_ids).float(),
                        dim=0,
                    )
                    .detach()
                    .cpu()
                    .tolist()
                )
                question_probabilities[item.question_id] = {
                    "A": float(values[0]),
                    "B": float(values[1]),
                }

            scores, order_gaps = aggregate_semantics(question_probabilities)
            action = action_from_semantics(state, scores)
            server_latency_ms = int(round((time.perf_counter() - server_started) * 1000))
            return CompanionDecisionResponse(
                action=action,
                semantic_scores=SemanticValues(**scores),
                semantic_order_gaps=SemanticValues(**order_gaps),
                usage=CompanionUsage(
                    input_tokens=sum(len(item.token_ids) for item in compiled),
                    output_tokens=0,
                ),
                server_latency_ms=server_latency_ms,
            )

    def warm_up(self) -> int:
        started = time.perf_counter()
        response = self.decide(
            CompanionDecisionRequest.model_validate(
                {
                    "state": {
                        "held_notes_count": 1,
                        "sustain_value": 0,
                        "recent_ioi_median_seconds": 0.4,
                        "recent_note_density_per_second": 3.0,
                        "seconds_since_last_note_on": 0.1,
                        "is_ai_playback_active": False,
                        "user_note_on_since_ai_playback_started": False,
                    }
                }
            ),
            server_started=started,
        )
        return response.server_latency_ms


CONFIG_KEY = web.AppKey("config", ServerConfig)
RUNTIME_KEY = web.AppKey("qwen_runtime", TransformersQwenRuntime)
BONJOUR_BROADCASTER_KEY = web.AppKey("bonjour_broadcaster", object)


def _error(code: str, *, status: int, message: str | None = None) -> web.Response:
    return web.json_response(
        CompanionErrorResponse(code=code, message=message).model_dump(),
        status=status,
    )


async def handle_health(request: web.Request) -> web.Response:
    return web.json_response(
        {
            "status": "ready",
            "service": "qwen_companion",
            "model": MODEL_ID,
            "device": "cuda",
            "path": COMPANION_DECISION_PATH,
            "protocol_version": PROTOCOL_VERSION,
            "engine": ENGINE_ID,
        }
    )


async def handle_companion_decision(request: web.Request) -> web.Response:
    try:
        payload = await request.json()
    except Exception:
        return _error("invalid_json", status=400)

    try:
        request_model = CompanionDecisionRequest.model_validate(payload)
    except Exception as exc:
        return _error("invalid_request", status=400, message=str(exc))

    server_started = time.perf_counter()
    runtime: TransformersQwenRuntime = request.app[RUNTIME_KEY]
    try:
        response = await asyncio.to_thread(
            runtime.decide,
            request_model,
            server_started=server_started,
        )
    except Exception:
        logger.exception("Qwen companion decision failed")
        return _error("decision_failed", status=500)

    return web.json_response(response.model_dump(), status=200)


async def _load_runtime(app: web.Application) -> None:
    runtime: TransformersQwenRuntime = app[RUNTIME_KEY]
    await asyncio.to_thread(runtime.load)
    latency_ms = await asyncio.to_thread(runtime.warm_up)
    logger.info("Qwen companion warm-up completed in %d ms", latency_ms)


async def _bonjour_start(app: web.Application) -> None:
    from shared.bonjour import BonjourServiceBroadcaster

    config: ServerConfig = app[CONFIG_KEY]
    broadcaster = BonjourServiceBroadcaster(
        service_type="_lpduet._tcp",
        instance_name="HappyPianist Qwen Companion",
        port=config.port,
        properties={
            b"path": COMPANION_DECISION_PATH.encode("utf-8"),
            b"protocol_version": PROTOCOL_VERSION.encode("utf-8"),
            b"engine": ENGINE_ID.encode("utf-8"),
            b"engine_impl": MODEL_ID.encode("utf-8"),
        },
    )
    await broadcaster.start()
    app[BONJOUR_BROADCASTER_KEY] = broadcaster


async def _bonjour_stop(app: web.Application) -> None:
    broadcaster = app.get(BONJOUR_BROADCASTER_KEY)
    if broadcaster is not None:
        await broadcaster.stop()


def create_app(config: ServerConfig) -> web.Application:
    app = web.Application()
    app[CONFIG_KEY] = config
    app[RUNTIME_KEY] = TransformersQwenRuntime()
    app.router.add_get("/health", handle_health)
    app.router.add_post(COMPANION_DECISION_PATH, handle_companion_decision)
    app.on_startup.append(_load_runtime)
    app.on_startup.append(_bonjour_start)
    app.on_cleanup.append(_bonjour_stop)
    return app


def main(argv: list[str] | None = None) -> None:
    logging.basicConfig(level=logging.INFO)
    config = parse_args(argv)
    print(f"[qwen_server] model={MODEL_ID}", flush=True)
    print("[qwen_server] device=cuda", flush=True)
    print(
        f"[qwen_server] listening=http://{config.host}:{config.port}{COMPANION_DECISION_PATH}",
        flush=True,
    )
    web.run_app(
        create_app(config),
        host=config.host,
        port=config.port,
        print=None,
    )


if __name__ == "__main__":
    main()
