#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PYTHON="${PYTHON:-python3.12}"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "Error: $PYTHON not found. Install Python 3.12 or run with: PYTHON=python3 ./scripts/run_server.sh" >&2
  exit 1
fi

if [ ! -d ".venv" ]; then
  "$PYTHON" -m venv .venv
fi

# shellcheck disable=SC1091
source .venv/bin/activate

PIP_PROGRESS_BAR=off python -m pip install -q -U pip
PIP_PROGRESS_BAR=off pip install -q -r requirements.txt

exec python -m uvicorn server.main:app --host 0.0.0.0 --port 8765
