import os
import time
from pathlib import Path

import torch
from transformers import AutoModelForCausalLM

from anticipation.config import TIME_RESOLUTION
from anticipation.convert import events_to_midi
from anticipation.vocab import DUR_OFFSET, NOTE_OFFSET, TIME_OFFSET, MAX_PITCH, REST
import anticipation.sample as sample


def ensure_mirror_env() -> None:
    os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")
    os.environ.setdefault("HF_HUB_ETAG_TIMEOUT", "120")
    os.environ.setdefault("HF_HUB_DOWNLOAD_TIMEOUT", "600")


def resolve_device() -> str:
    explicit = os.environ.get("AMT_DEVICE")
    if explicit:
        return explicit

    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def resolve_model_path() -> str:
    explicit_dir = os.environ.get("AMT_MODEL_DIR")
    if explicit_dir:
        return explicit_dir

    default_dir = Path(__file__).resolve().parents[1] / "models" / "music-small-800k"
    if default_dir.exists():
        return str(default_dir)

    return os.environ.get("AMT_MODEL_ID", "stanford-crfm/music-small-800k")


def quantize_seconds(seconds: float) -> int:
    return max(0, int(round(seconds * TIME_RESOLUTION)))


def notes_to_events(notes: list[dict], instrument: int = 0) -> list[int]:
    # arrival-time 事件表示： [TIME_OFFSET+t, DUR_OFFSET+d, NOTE_OFFSET+(instr*128 + pitch)]
    events: list[int] = []
    for note in notes:
        pitch = int(note["note"])
        t = quantize_seconds(float(note["time"]))
        d = max(1, quantize_seconds(float(note["duration"])))
        note_id = instrument * MAX_PITCH + pitch
        events.extend([TIME_OFFSET + t, DUR_OFFSET + d, NOTE_OFFSET + note_id])
    return events


def build_motif() -> list[dict]:
    # 一个极短动机：C major 上行 + 回落（时间单位：秒）
    # 目标不是“旋律多好”，而是验证 “输入动机 → 生成回应” 的链路与对话感。
    return [
        {"note": 60, "time": 0.0, "duration": 0.35, "velocity": 90},
        {"note": 62, "time": 0.4, "duration": 0.35, "velocity": 90},
        {"note": 64, "time": 0.8, "duration": 0.35, "velocity": 90},
        {"note": 67, "time": 1.2, "duration": 0.50, "velocity": 95},
        {"note": 64, "time": 1.8, "duration": 0.40, "velocity": 88},
    ]


def main() -> None:
    ensure_mirror_env()

    old_safe_logits = sample.safe_logits

    def safe_logits_fixed(logits, idx):  # type: ignore[no-untyped-def]
        logits = old_safe_logits(logits, idx)
        if idx % 3 != 2:
            logits[REST] = -float("inf")
        return logits

    sample.safe_logits = safe_logits_fixed  # type: ignore[assignment]

    model_ref = resolve_model_path()
    device = resolve_device()
    print(f"model: {model_ref}")
    print(f"device: {device}")

    if Path(model_ref).is_dir():
        has_weights = any(Path(model_ref).glob("*.safetensors")) or any(Path(model_ref).glob("pytorch_model*.bin"))
        if not has_weights:
            raise SystemExit(
                f"Model directory exists but weights not found: {model_ref}\n"
                "Hint: run HF mirror download in tmux first:\n"
                "  tmux attach -t piano-dialogue-p1\n"
            )

    t0 = time.time()
    model = AutoModelForCausalLM.from_pretrained(model_ref)
    model.to(device)
    model.eval()
    print(f"loaded in {time.time() - t0:.2f}s")

    motif = build_motif()
    motif_events = notes_to_events(motif, instrument=0)

    top_p = float(os.environ.get("AMT_TOP_P", "0.95"))
    start_time = float(os.environ.get("AMT_INFILL_START_SEC", "2.0"))
    end_time = float(os.environ.get("AMT_INFILL_END_SEC", "8.0"))

    t1 = time.time()
    # start_time=2s：让动机作为 prompt；让模型从 2s 开始续写到 8s（更像“你弹一句→AI回一句”）
    events = sample.generate(model, start_time=start_time, end_time=end_time, inputs=motif_events, top_p=top_p)
    print(f"generated {len(events)} tokens in {time.time() - t1:.2f}s")

    out_dir = Path(__file__).resolve().parents[1] / "out"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "output_infilling.mid"

    mid = events_to_midi(events)
    mid.save(str(out_path))
    print(f"wrote: {out_path}")


if __name__ == "__main__":
    main()
