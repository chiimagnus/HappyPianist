#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

MODEL_ID="${AMT_MODEL_ID:-stanford-crfm/music-small-800k}"
MODEL_DIR="${AMT_MODEL_DIR:-models/music-small-800k}"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

mkdir -p "$MODEL_DIR"

echo "HF_ENDPOINT=$HF_ENDPOINT"
echo "MODEL_ID=$MODEL_ID"
echo "MODEL_DIR=$MODEL_DIR"

download_one() {
  local filename="$1"
  local out="$MODEL_DIR/$filename"
  local url="${HF_ENDPOINT}/${MODEL_ID}/resolve/main/${filename}"

  echo "Downloading ${filename} (resume supported)..."
  # 注意：这个文件很大；若网络很慢，建议改用浏览器下载器更稳。
  # -f: 4xx/5xx 直接失败，便于 fallback
  curl -fL -C - -o "$out" "$url"
  echo "Done: $out"
}

echo "Trying model.safetensors first, then pytorch_model.bin..."
if download_one "model.safetensors"; then
  exit 0
fi

download_one "pytorch_model.bin"
