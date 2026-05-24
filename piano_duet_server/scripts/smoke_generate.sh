#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PORT="${PORT:-8766}"
HOST="127.0.0.1"
BASE_URL="http://${HOST}:${PORT}"

cleanup() {
  if [ -n "${SERVER_PID:-}" ]; then
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

PYTHON="${PYTHON:-}"
if [ -z "$PYTHON" ]; then
  if command -v python3.10 >/dev/null 2>&1; then
    PYTHON="python3.10"
  elif command -v python3.12 >/dev/null 2>&1; then
    PYTHON="python3.12"
  else
    PYTHON="python3"
  fi
fi

if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "Error: $PYTHON not found. Install Python 3.10+ or run with: PYTHON=python3 ./scripts/smoke_generate.sh" >&2
  exit 1
fi

if [ ! -d ".venv" ]; then
  "$PYTHON" -m venv .venv
fi

# shellcheck disable=SC1091
source .venv/bin/activate

PIP_PROGRESS_BAR=off python -m pip install -q -U pip
PIP_PROGRESS_BAR=off pip install -q -r requirements.txt

python -m uvicorn server.api.main:app --host 0.0.0.0 --port "$PORT" >/tmp/piano_duet_server_smoke.log 2>&1 &
SERVER_PID=$!

echo "waiting for server..."
for _ in $(seq 1 50); do
  if curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done

health_json="$(curl -fsS "${BASE_URL}/health")"
if ! echo "$health_json" | rg -q "\"status\"\\s*:\\s*\"ok\""; then
  echo "health failed: ${health_json}"
  echo "--- server log ---"
  tail -n 200 /tmp/piano_duet_server_smoke.log || true
  exit 1
fi
echo "health ok"

payload='{
  "type": "generate",
  "protocol_version": 1,
  "notes": [
    {"note": 60, "velocity": 90, "time": 0.0, "duration": 0.3},
    {"note": 64, "velocity": 90, "time": 0.3, "duration": 0.3},
    {"note": 67, "velocity": 90, "time": 0.6, "duration": 0.3}
  ],
  "params": {"top_p": 0.95, "max_tokens": 128, "strategy": "deterministic"}
}'

response="$(curl -fsS -H 'Content-Type: application/json' -d "$payload" "${BASE_URL}/generate")"
reply_notes_count="$(echo "$response" | python -c 'import json,sys; print(len(json.loads(sys.stdin.read()).get("notes", [])))')"

if [ "${reply_notes_count}" -le 0 ]; then
  echo "generate failed: reply_notes_count<=0"
  echo "$response"
  echo "--- server log ---"
  tail -n 200 /tmp/piano_duet_server_smoke.log || true
  exit 1
fi

echo "generate ok reply_notes_count=${reply_notes_count}"
