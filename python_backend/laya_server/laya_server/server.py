from __future__ import annotations

import argparse
import asyncio
from dataclasses import dataclass
import logging
import threading
import time
from typing import Any

from aiohttp import web

from shared.laya_protocol import (
    ChoiceQuestion,
    ClassifierErrorResponse,
    ClassifierRequest,
    ClassifierResponse,
)


logger = logging.getLogger(__name__)
DEFAULT_MODEL = "aac6fef/laya-multilingual-mlx"


@dataclass(frozen=True)
class ServerConfig:
    host: str
    port: int
    model: str


def parse_args(argv: list[str] | None = None) -> ServerConfig:
    parser = argparse.ArgumentParser(prog="laya_server", add_help=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8767)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    args = parser.parse_args(argv)
    return ServerConfig(
        host=str(args.host),
        port=int(args.port),
        model=str(args.model),
    )


class LayaRuntime:
    def __init__(self, model_name_or_path: str):
        self._model_name_or_path = model_name_or_path
        self._lock = threading.Lock()
        self._agent: Any | None = None

    def load(self) -> None:
        with self._lock:
            if self._agent is not None:
                return

            import laya_mlx as laya

            self._agent = laya.load(self._model_name_or_path)
            logger.info("Laya runtime loaded: model=%s", self._model_name_or_path)

    def classify(self, request: ClassifierRequest) -> ClassifierResponse:
        with self._lock:
            if self._agent is None:
                raise RuntimeError("Laya runtime is not loaded")
            if request.model != self._model_name_or_path:
                raise ValueError(
                    f"request model {request.model!r} does not match "
                    f"loaded model {self._model_name_or_path!r}"
                )

            questions = {
                question_id: question.model_dump(exclude_none=True)
                for question_id, question in request.questions.items()
            }
            started = time.perf_counter()
            payload = self._agent.predict(request.state, questions)
            latency_ms = int(round((time.perf_counter() - started) * 1000))

            if not isinstance(payload, dict):
                raise RuntimeError("Laya returned a non-object response")
            usage = payload.get("usage")
            if not isinstance(usage, dict) or usage.get("output_tokens") != 0:
                raise RuntimeError("Laya response violated the zero-output-token contract")
            answers = payload.get("answers")
            if not isinstance(answers, dict) or set(answers) != set(request.questions):
                raise RuntimeError("Laya response answer keys do not match the request")

            return ClassifierResponse.model_validate(
                {
                    "model": self._model_name_or_path,
                    "answers": answers,
                    "usage": usage,
                    "latency_ms": latency_ms,
                }
            )

    def warm_up(self) -> int:
        response = self.classify(
            ClassifierRequest(
                model=self._model_name_or_path,
                state={"warm_up": True},
                questions={
                    "ready": ChoiceQuestion(
                        instructions="Is the local decision runtime ready?",
                        criteria={
                            "yes": "The runtime is ready.",
                            "no": "The runtime is not ready.",
                        },
                    )
                },
            )
        )
        return response.latency_ms


CONFIG_KEY = web.AppKey("config", ServerConfig)
RUNTIME_KEY = web.AppKey("laya_runtime", LayaRuntime)
BONJOUR_BROADCASTER_KEY = web.AppKey("bonjour_broadcaster", object)


async def handle_health(request: web.Request) -> web.Response:
    config: ServerConfig = request.app[CONFIG_KEY]
    return web.json_response(
        {
            "status": "ready",
            "service": "laya_classifier",
            "model": config.model,
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

    config: ServerConfig = request.app[CONFIG_KEY]
    if request_model.model != config.model:
        return web.json_response(
            ClassifierErrorResponse(
                message=(
                    f"request model {request_model.model!r} does not match "
                    f"loaded model {config.model!r}"
                )
            ).model_dump(),
            status=400,
        )

    runtime: LayaRuntime = request.app[RUNTIME_KEY]
    try:
        response = await asyncio.to_thread(runtime.classify, request_model)
    except ValueError as exc:
        return web.json_response(
            ClassifierErrorResponse(message=str(exc)).model_dump(),
            status=400,
        )
    except Exception:
        logger.exception("Laya classification failed")
        return web.json_response(
            ClassifierErrorResponse(message="classification_failed").model_dump(),
            status=500,
        )

    return web.json_response(response.model_dump(), status=200)


async def _load_runtime(app: web.Application) -> None:
    runtime: LayaRuntime = app[RUNTIME_KEY]
    await asyncio.to_thread(runtime.load)
    latency_ms = await asyncio.to_thread(runtime.warm_up)
    logger.info("Laya runtime warm-up completed in %d ms", latency_ms)


async def _bonjour_start(app: web.Application) -> None:
    from shared.bonjour import BonjourServiceBroadcaster

    config: ServerConfig = app[CONFIG_KEY]
    broadcaster = BonjourServiceBroadcaster(
        service_type="_lpduet._tcp",
        instance_name="HappyPianist Laya Classifier",
        port=config.port,
        properties={
            b"path": b"/v1/classifier",
            b"protocol_version": b"1",
            b"engine": b"laya-mlx",
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
    app[RUNTIME_KEY] = LayaRuntime(config.model)
    app.router.add_get("/health", handle_health)
    app.router.add_post("/v1/classifier", handle_classifier)
    app.on_startup.append(_load_runtime)
    app.on_startup.append(_bonjour_start)
    app.on_cleanup.append(_bonjour_stop)
    return app


def main(argv: list[str] | None = None) -> None:
    logging.basicConfig(level=logging.INFO)
    config = parse_args(argv)
    print(f"[laya_server] model={config.model}", flush=True)
    print(
        f"[laya_server] listening=http://{config.host}:{config.port}/v1/classifier",
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
