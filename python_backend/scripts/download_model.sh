#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}/../duet"

PRIMARY_NAME="performance_with_dynamics_and_modkey.mag"
PRIMARY_URL="http://download.magenta.tensorflow.org/models/${PRIMARY_NAME}"

FALLBACK_NAME="performance_with_dynamics.mag"
FALLBACK_URL="http://download.magenta.tensorflow.org/models/${FALLBACK_NAME}"

mkdir -p models

if [ -f "models/${PRIMARY_NAME}" ]; then
  echo "model exists: models/${PRIMARY_NAME}"
  ls -lh "models/${PRIMARY_NAME}"
  exit 0
fi
if [ -f "models/${FALLBACK_NAME}" ]; then
  echo "model exists: models/${FALLBACK_NAME}"
  ls -lh "models/${FALLBACK_NAME}"
  exit 0
fi

try_download() {
  local name="$1"
  local url="$2"
  echo "downloading: ${url}"
  if curl -fL --retry 3 --retry-delay 1 -o "models/${name}" "${url}"; then
    echo "download ok: models/${name}"
    ls -lh "models/${name}"
    return 0
  fi
  rm -f "models/${name}" || true
  return 1
}

if try_download "${PRIMARY_NAME}" "${PRIMARY_URL}"; then
  exit 0
fi

echo "primary model unavailable, fallback to: ${FALLBACK_URL}"
try_download "${FALLBACK_NAME}" "${FALLBACK_URL}"
