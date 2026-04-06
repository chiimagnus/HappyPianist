import os
import time
from pathlib import Path

import torch
from transformers import AutoModelForCausalLM

from anticipation.convert import events_to_midi
from anticipation.vocab import REST
import anticipation.sample as sample


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


def ensure_mirror_env() -> None:
    # 用户要求默认走 HF 镜像；若你本机网络直连更快，手动覆盖 HF_ENDPOINT 即可。
    os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")
    os.environ.setdefault("HF_HUB_ETAG_TIMEOUT", "120")
    os.environ.setdefault("HF_HUB_DOWNLOAD_TIMEOUT", "600")


def main() -> None:
    ensure_mirror_env()

    # Patch anticipation sampling:
    # The official sampling helper masks NOTE tokens in duration/time slots but does not mask `REST`,
    # which can lead to invalid sequences like (time, REST, note) and crash MIDI conversion.
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

    top_p = float(os.environ.get("AMT_TOP_P", "0.95"))
    length_sec = float(os.environ.get("AMT_LENGTH_SEC", "8"))

    t1 = time.time()
    events = sample.generate(model, start_time=0, end_time=length_sec, top_p=top_p)
    print(f"generated {len(events)} tokens in {time.time() - t1:.2f}s")

    out_dir = Path(__file__).resolve().parents[1] / "out"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "output.mid"

    mid = events_to_midi(events)
    mid.save(str(out_path))
    print(f"wrote: {out_path}")


if __name__ == "__main__":
    main()
