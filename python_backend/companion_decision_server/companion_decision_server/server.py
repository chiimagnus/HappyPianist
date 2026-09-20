from __future__ import annotations

import argparse
import asyncio
import logging
import threading
import time
from dataclasses import dataclass
from typing import Any

from aiohttp import web

from shared.decision_protocol import (
    CompanionDecisionInputV2,
    DecisionErrorResponseV2,
    DecisionRequestV2,
    DecisionResponseV2,
)

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """你是实时钢琴陪伴决策器。根据音乐交互语义选择一个动作。
A=继续听：用户仍在主导演奏，或当前停顿更像乐句内部停顿，不应抢先参与。
B=轻量陪奏：用户仍在演奏但有足够空间，AI可以柔和加入。
C=稀疏陪奏：允许参与，但必须显著降低音符密度，为用户留出主要空间。
D=让位：AI正在演奏，而用户重新明显主导，AI应该停止或退出。
E=回应：用户的乐句已经明显结束，并且现在适合由AI接一句。
不要解释，不要生成任何其他内容，只输出一个大写字母。"""

ACTION_LABELS = {
    "A": "listen",
    "B": "support",
    "C": "sparse",
    "D": "yield",
    "E": "respond",
}


@dataclass(frozen=True)
class ServerConfig:
    host: str
    port: int
    model: str
    device: str


def parse_args(argv: list[str] | None = None) -> ServerConfig:
    parser = argparse.ArgumentParser(prog="companion_decision_server", add_help=True)
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


def _seconds_since(now: float, timestamp: float | None) -> str:
    if timestamp is None:
        return "-"
    return f"{max(0.0, now - timestamp):.3f}"


def format_decision_state(input_model: CompanionDecisionInputV2) -> str:
    recent_notes = ", ".join(
        (
            f"{note.midi}(v={note.velocity},"
            f"ago={note.onset_seconds_ago:.3f}s,d={note.duration_seconds:.3f}s)"
        )
        for note in input_model.recent_notes
    )
    if recent_notes == "":
        recent_notes = "无"

    return "\n".join(
        [
            "最近演奏状态：",
            f"当前按住音符={input_model.held_notes_count}",
            f"延音踏板值={input_model.sustain_value}",
            f"最近音符间隔中位数={input_model.recent_ioi_median_seconds if input_model.recent_ioi_median_seconds is not None else '-'}",
            f"最近音符密度={input_model.recent_note_density_per_second:.3f}音/秒",
            f"力度趋势={input_model.recent_velocity_trend:.3f}",
            f"距最后用户事件={_seconds_since(input_model.now_timestamp_seconds, input_model.last_user_event_timestamp_seconds)}秒",
            f"距最后一次按键={_seconds_since(input_model.now_timestamp_seconds, input_model.last_note_on_timestamp_seconds)}秒",
            f"当前音高中心={input_model.active_pitch_center if input_model.active_pitch_center is not None else '-'}",
            f"AI当前正在演奏={'是' if input_model.is_ai_playback_active else '否'}",
            f"最近音符={recent_notes}",
            "请选择动作。",
        ]
    )


class QwenDecisionPipeline:
    def __init__(self, model_name_or_path: str, device: str):
        self._model_name_or_path = model_name_or_path
        self._device = device
        self._lock = threading.Lock()
        self._tokenizer: Any | None = None
        self._model: Any | None = None
        self._candidate_ids: dict[str, int] = {}

    def load(self) -> None:
        with self._lock:
            if self._model is not None:
                return

            import torch
            from transformers import AutoTokenizer, Qwen3_5ForConditionalGeneration

            if self._device == "cuda":
                if torch.cuda.is_available() is False:
                    raise RuntimeError("CUDA device selected but torch.cuda is unavailable")
                dtype = torch.bfloat16
            elif self._device == "cpu":
                dtype = torch.float32
            else:
                raise ValueError(f"unsupported decision device: {self._device}")

            tokenizer = AutoTokenizer.from_pretrained(self._model_name_or_path)
            model = Qwen3_5ForConditionalGeneration.from_pretrained(
                self._model_name_or_path,
                dtype=dtype,
            )
            model.eval().to(self._device)

            candidate_ids: dict[str, int] = {}
            for label in ACTION_LABELS:
                token_ids = tokenizer.encode(label, add_special_tokens=False)
                if len(token_ids) != 1:
                    raise RuntimeError(
                        f"decision label {label!r} must encode to one token, got {token_ids}"
                    )
                candidate_ids[label] = int(token_ids[0])

            self._tokenizer = tokenizer
            self._model = model
            self._candidate_ids = candidate_ids
            logger.info(
                "Qwen decision model loaded: model=%s device=%s",
                self._model_name_or_path,
                self._device,
            )

    def warm_up(self) -> int:
        _, _, _, latency_ms = self.decide(
            CompanionDecisionInputV2(
                now_timestamp_seconds=1.0,
                held_notes_count=0,
                sustain_value=0,
                recent_ioi_median_seconds=None,
                recent_velocity_trend=0.0,
                recent_note_density_per_second=0.0,
                last_user_event_timestamp_seconds=None,
                last_note_on_timestamp_seconds=None,
                active_pitch_center=None,
                is_ai_playback_active=False,
                recent_notes=[],
            )
        )
        return latency_ms

    def decide(
        self,
        input_model: CompanionDecisionInputV2,
    ) -> tuple[str, float, dict[str, float], int]:
        with self._lock:
            if self._model is None or self._tokenizer is None:
                raise RuntimeError("decision model is not loaded")

            import torch

            messages = [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": format_decision_state(input_model)},
            ]
            input_ids = self._tokenizer.apply_chat_template(
                messages,
                tokenize=True,
                add_generation_prompt=True,
                return_tensors="pt",
            )
            if hasattr(input_ids, "input_ids"):
                input_ids = input_ids.input_ids
            input_ids = input_ids.to(self._device)

            if self._device == "cuda":
                torch.cuda.synchronize()
            started = time.perf_counter()
            with torch.inference_mode():
                logits = self._model(input_ids=input_ids, use_cache=False).logits[0, -1]
            selected_ids = torch.tensor(
                [self._candidate_ids[label] for label in ACTION_LABELS],
                device=logits.device,
            )
            scores = torch.softmax(logits.index_select(0, selected_ids).float(), dim=0)
            if self._device == "cuda":
                torch.cuda.synchronize()
            latency_ms = int(round((time.perf_counter() - started) * 1000))

            raw_probabilities = scores.detach().cpu().tolist()
            probabilities = {
                ACTION_LABELS[label]: float(probability)
                for label, probability in zip(ACTION_LABELS, raw_probabilities)
            }
            action = max(probabilities, key=probabilities.get)
            confidence = probabilities[action]
            return action, confidence, probabilities, latency_ms


CONFIG_KEY = web.AppKey("config", ServerConfig)
PIPELINE_KEY = web.AppKey("qwen_decision_pipeline", QwenDecisionPipeline)
BONJOUR_BROADCASTER_KEY = web.AppKey("bonjour_broadcaster", object)


async def handle_root(request: web.Request) -> web.Response:
    config: ServerConfig = request.app[CONFIG_KEY]
    return web.json_response(
        {
            "service": "companion_decision_server",
            "protocol_version": 2,
            "model": config.model,
            "device": config.device,
        }
    )


async def handle_decision(request: web.Request) -> web.Response:
    try:
        payload = await request.json()
    except Exception:
        return web.json_response(
            DecisionErrorResponseV2(message="invalid_json").model_dump(),
            status=400,
        )

    try:
        request_model = DecisionRequestV2.model_validate(payload)
    except Exception as exc:
        return web.json_response(
            DecisionErrorResponseV2(message=f"invalid_request: {exc}").model_dump(),
            status=400,
        )

    pipeline: QwenDecisionPipeline = request.app[PIPELINE_KEY]
    try:
        action, confidence, probabilities, latency_ms = await asyncio.to_thread(
            pipeline.decide,
            request_model.input,
        )
    except Exception:
        logger.exception("Qwen companion decision failed")
        return web.json_response(
            DecisionErrorResponseV2(message="decision_failed").model_dump(),
            status=500,
        )

    config: ServerConfig = request.app[CONFIG_KEY]
    response = DecisionResponseV2(
        action=action,
        confidence=confidence,
        probabilities=probabilities,
        latency_ms=latency_ms,
        model=config.model,
    )
    return web.json_response(response.model_dump(), status=200)


async def _load_pipeline(app: web.Application) -> None:
    pipeline: QwenDecisionPipeline = app[PIPELINE_KEY]
    await asyncio.to_thread(pipeline.load)
    latency_ms = await asyncio.to_thread(pipeline.warm_up)
    logger.info("Qwen decision warm-up completed in %d ms", latency_ms)


async def _bonjour_start(app: web.Application) -> None:
    from shared.bonjour import BonjourServiceBroadcaster

    config: ServerConfig = app[CONFIG_KEY]
    txt = {
        "path": "/decision",
        "protocol_version": "2",
        "engine": "qwen3.5-decision",
        "engine_impl": config.model,
    }
    broadcaster = BonjourServiceBroadcaster(
        service_type="_lpduet._tcp",
        instance_name="HappyPianist Qwen Decision",
        port=config.port,
        properties={
            key.encode("utf-8"): value.encode("utf-8")
            for key, value in txt.items()
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
    app[PIPELINE_KEY] = QwenDecisionPipeline(
        model_name_or_path=config.model,
        device=config.device,
    )
    app.router.add_get("/", handle_root)
    app.router.add_post("/decision", handle_decision)
    app.on_startup.append(_load_pipeline)
    app.on_startup.append(_bonjour_start)
    app.on_cleanup.append(_bonjour_stop)
    return app


def main(argv: list[str] | None = None) -> None:
    logging.basicConfig(level=logging.INFO)
    config = parse_args(argv)
    print(f"[companion_decision_server] model={config.model}", flush=True)
    print(f"[companion_decision_server] device={config.device}", flush=True)
    print(
        f"[companion_decision_server] listening=http://{config.host}:{config.port}/decision",
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
