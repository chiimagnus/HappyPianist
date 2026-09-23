from __future__ import annotations

import argparse
import asyncio
import logging
import threading
import time
from dataclasses import dataclass
from typing import Any

from aiohttp import web

from shared.jev_protocol import (
    ChoiceAnswer,
    ChoiceQuestion,
    ClassifierErrorResponse,
    ClassifierRequest,
    ClassifierResponse,
    ClassifierUsage,
    NoulAnswer,
    NoulQuestion,
    NoulRating,
    PromptPlan,
    build_choice_prompt,
    build_noul_prompt,
)

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ServerConfig:
    host: str
    port: int
    model: str
    device: str


def parse_args(argv: list[str] | None = None) -> ServerConfig:
    parser = argparse.ArgumentParser(prog="jev_server", add_help=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8767)
    parser.add_argument("--model", default="Qwen/Qwen3.5-0.8B")
    parser.add_argument("--device", choices=("cuda", "cpu"), default="cuda")
    args = parser.parse_args(argv)
    return ServerConfig(
        host=args.host,
        port=args.port,
        model=str(args.model),
        device=str(args.device),
    )


@dataclass(frozen=True)
class CompiledQuestion:
    question_id: str
    question_type: str
    token_ids: list[int]
    candidate_ids: list[int]
    choices: list[str]


class TransformersJevRuntime:
    def __init__(self, model_name_or_path: str, device: str):
        self._model_name_or_path = model_name_or_path
        self._device = device
        self._lock = threading.Lock()
        self._tokenizer: Any | None = None
        self._model: Any | None = None

    def load(self) -> None:
        with self._lock:
            if self._model is not None:
                return

            import torch
            from transformers import AutoModelForCausalLM, AutoTokenizer

            if self._device == "cuda":
                if torch.cuda.is_available() is False:
                    raise RuntimeError("CUDA device selected but torch.cuda is unavailable")
                dtype = torch.bfloat16
            else:
                dtype = torch.float32

            tokenizer = AutoTokenizer.from_pretrained(self._model_name_or_path)
            model = AutoModelForCausalLM.from_pretrained(
                self._model_name_or_path,
                dtype=dtype,
            )
            model.eval().to(self._device)

            self._tokenizer = tokenizer
            self._model = model
            logger.info(
                "Jev runtime loaded: model=%s device=%s",
                self._model_name_or_path,
                self._device,
            )

    def _render_plan(self, plan: PromptPlan) -> tuple[list[int], list[int]]:
        if self._tokenizer is None:
            raise RuntimeError("Jev runtime is not loaded")

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
        if len(set(candidate_ids)) != len(candidate_ids):
            return token_ids, []
        return token_ids, candidate_ids

    def _compile_question(
        self,
        request: ClassifierRequest,
        question_id: str,
    ) -> CompiledQuestion:
        question = request.questions[question_id]
        if isinstance(question, NoulQuestion):
            plan = build_noul_prompt(
                request.state,
                request.questions,
                question_id,
            )
            token_ids, candidate_ids = self._render_plan(plan)
            if not candidate_ids:
                raise RuntimeError(
                    f"noul labels for {question_id!r} are not single-token stable"
                )
            return CompiledQuestion(
                question_id=question_id,
                question_type="noul",
                token_ids=token_ids,
                candidate_ids=candidate_ids,
                choices=plan.choices,
            )

        plan = build_choice_prompt(
            request.state,
            request.questions,
            question_id,
        )
        token_ids, candidate_ids = self._render_plan(plan)
        if not candidate_ids:
            raise RuntimeError(
                f"choice labels for {question_id!r} are not single-token stable"
            )
        return CompiledQuestion(
            question_id=question_id,
            question_type="choice",
            token_ids=token_ids,
            candidate_ids=candidate_ids,
            choices=plan.choices,
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
            device=self._device,
        )
        attention_mask = torch.zeros(
            (len(compiled), max_length),
            dtype=torch.long,
            device=self._device,
        )
        for row, item in enumerate(compiled):
            length = len(item.token_ids)
            input_ids[row, :length] = torch.tensor(
                item.token_ids,
                dtype=torch.long,
                device=self._device,
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

    def classify(self, request: ClassifierRequest) -> ClassifierResponse:
        with self._lock:
            if self._model is None or self._tokenizer is None:
                raise RuntimeError("Jev runtime is not loaded")
            if request.model != self._model_name_or_path:
                raise ValueError(
                    f"request model {request.model!r} does not match "
                    f"loaded model {self._model_name_or_path!r}"
                )

            import torch

            compiled = [
                self._compile_question(request, question_id)
                for question_id in sorted(request.questions)
            ]
            pad_token_id = self._tokenizer.pad_token_id
            if pad_token_id is None:
                pad_token_id = self._tokenizer.eos_token_id
            if pad_token_id is None:
                raise RuntimeError("tokenizer has no pad or eos token")

            if self._device == "cuda":
                torch.cuda.synchronize()
            started = time.perf_counter()
            with torch.inference_mode():
                last_logits = self._forward_full(
                    compiled,
                    torch,
                    int(pad_token_id),
                )
            if self._device == "cuda":
                torch.cuda.synchronize()
            latency_ms = int(round((time.perf_counter() - started) * 1000))

            answers: dict[str, ChoiceAnswer | NoulAnswer] = {}
            for item, logits in zip(compiled, last_logits):
                selected_ids = torch.tensor(
                    item.candidate_ids,
                    device=logits.device,
                )
                scores = torch.softmax(
                    logits.index_select(0, selected_ids).float(),
                    dim=0,
                )
                values = scores.detach().cpu().tolist()
                probabilities = {
                    choice: float(probability)
                    for choice, probability in zip(item.choices, values)
                }

                if item.question_type == "noul":
                    expected_score = sum(
                        float(label) * probability
                        for label, probability in probabilities.items()
                    )
                    noul = expected_score / 10.0
                    answers[item.question_id] = NoulAnswer(
                        noul=noul,
                        rating=NoulRating(
                            expected_score=expected_score,
                            probabilities=probabilities,
                        ),
                    )
                else:
                    choice = max(probabilities, key=probabilities.get)
                    answers[item.question_id] = ChoiceAnswer(
                        choice=choice,
                        confidence=probabilities[choice],
                        probabilities=probabilities,
                    )

            return ClassifierResponse(
                model=self._model_name_or_path,
                answers=answers,
                usage=ClassifierUsage(
                    input_tokens=sum(len(item.token_ids) for item in compiled),
                    output_tokens=0,
                ),
                latency_ms=latency_ms,
            )

    def warm_up(self) -> int:
        response = self.classify(
            ClassifierRequest(
                model=self._model_name_or_path,
                state={"warm_up": True},
                questions={
                    "ready": ChoiceQuestion(
                        instructions="Is this classifier ready?",
                        criteria={
                            "yes": "The classifier is ready.",
                            "no": "The classifier is not ready.",
                        },
                    )
                },
            )
        )
        return response.latency_ms


CONFIG_KEY = web.AppKey("config", ServerConfig)
RUNTIME_KEY = web.AppKey("jev_runtime", TransformersJevRuntime)
BONJOUR_BROADCASTER_KEY = web.AppKey("bonjour_broadcaster", object)


async def handle_health(request: web.Request) -> web.Response:
    config: ServerConfig = request.app[CONFIG_KEY]
    return web.json_response(
        {
            "status": "ready",
            "service": "jev_classifier",
            "model": config.model,
            "device": config.device,
        }
    )


async def handle_classifier(request: web.Request) -> web.Response:
    try:
        payload = await request.json()
    except Exception:
        return web.json_response(
            ClassifierErrorResponse(message="invalid_json").model_dump(),
            status=400,
        )

    try:
        request_model = ClassifierRequest.model_validate(payload)
    except Exception as exc:
        return web.json_response(
            ClassifierErrorResponse(message=f"invalid_request: {exc}").model_dump(),
            status=400,
        )

    runtime: TransformersJevRuntime = request.app[RUNTIME_KEY]
    try:
        response = await asyncio.to_thread(runtime.classify, request_model)
    except ValueError as exc:
        return web.json_response(
            ClassifierErrorResponse(message=str(exc)).model_dump(),
            status=400,
        )
    except Exception:
        logger.exception("Jev classification failed")
        return web.json_response(
            ClassifierErrorResponse(message="classification_failed").model_dump(),
            status=500,
        )

    return web.json_response(response.model_dump(), status=200)


async def _load_runtime(app: web.Application) -> None:
    runtime: TransformersJevRuntime = app[RUNTIME_KEY]
    await asyncio.to_thread(runtime.load)
    latency_ms = await asyncio.to_thread(runtime.warm_up)
    logger.info("Jev runtime warm-up completed in %d ms", latency_ms)


async def _bonjour_start(app: web.Application) -> None:
    from shared.bonjour import BonjourServiceBroadcaster

    config: ServerConfig = app[CONFIG_KEY]
    broadcaster = BonjourServiceBroadcaster(
        service_type="_lpduet._tcp",
        instance_name="HappyPianist Jev Classifier",
        port=config.port,
        properties={
            b"path": b"/v1/classifier",
            b"protocol_version": b"1",
            b"engine": b"jev-classifier",
            b"engine_impl": config.model.encode("utf-8"),
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
    app[RUNTIME_KEY] = TransformersJevRuntime(
        model_name_or_path=config.model,
        device=config.device,
    )
    app.router.add_get("/health", handle_health)
    app.router.add_post("/v1/classifier", handle_classifier)
    app.on_startup.append(_load_runtime)
    app.on_startup.append(_bonjour_start)
    app.on_cleanup.append(_bonjour_stop)
    return app


def main(argv: list[str] | None = None) -> None:
    logging.basicConfig(level=logging.INFO)
    config = parse_args(argv)
    print(f"[jev_server] model={config.model}", flush=True)
    print(f"[jev_server] device={config.device}", flush=True)
    print(
        f"[jev_server] listening=http://{config.host}:{config.port}/v1/classifier",
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
