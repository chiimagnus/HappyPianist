from __future__ import annotations

from pathlib import Path

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig

BASE_MODEL_ID = "Qwen/Qwen3.5-0.8B"
PYTHON_BACKEND_ROOT = Path(__file__).resolve().parents[1]
TARGET_DIR = PYTHON_BACKEND_ROOT / ".models" / "qwen3.5-0.8b-bnb-4bit"


def main() -> None:
    if torch.cuda.is_available() is False:
        raise RuntimeError("Qwen 4-bit preparation requires CUDA")
    if TARGET_DIR.exists():
        raise RuntimeError(f"4-bit checkpoint already exists: {TARGET_DIR}")

    quantization_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_use_double_quant=True,
        bnb_4bit_compute_dtype=torch.bfloat16,
    )
    tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL_ID, local_files_only=True)
    model = AutoModelForCausalLM.from_pretrained(
        BASE_MODEL_ID,
        quantization_config=quantization_config,
        device_map={"": "cuda"},
        local_files_only=True,
    )

    TARGET_DIR.mkdir(parents=True)
    model.save_pretrained(TARGET_DIR, safe_serialization=True)
    tokenizer.save_pretrained(TARGET_DIR)
    print(f"[prepare_qwen_4bit] saved={TARGET_DIR}")


if __name__ == "__main__":
    main()
