#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DUET_ENGINE="${DUET_ENGINE:-placeholder}"
VENV_DIR=".venv"
if [ "$DUET_ENGINE" = "magenta" ]; then
  VENV_DIR=".venv-magenta"
fi

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

if [ "$DUET_ENGINE" = "magenta" ]; then
  py_ver="$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  if [ "$py_ver" != "3.9" ]; then
    echo "Error: DUET_ENGINE=magenta requires Python 3.9 (got ${py_ver})." >&2
    echo "Install python3.9 and run: PYTHON=python3.9 DUET_ENGINE=magenta ./scripts/smoke_generate.sh" >&2
    exit 1
  fi
fi

desired_py_ver="$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [ -d "$VENV_DIR" ]; then
  venv_py_ver=""
  if [ -x "$VENV_DIR/bin/python" ]; then
    venv_py_ver="$("$VENV_DIR/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
  fi
  if [ -n "$venv_py_ver" ] && [ "$venv_py_ver" != "$desired_py_ver" ]; then
    echo "Existing ${VENV_DIR} uses Python ${venv_py_ver}; recreating with Python ${desired_py_ver}..." >&2
    rm -rf "$VENV_DIR"
  fi
fi

if [ ! -d "$VENV_DIR" ]; then
  "$PYTHON" -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

PIP_PROGRESS_BAR=off python -m pip install -q -U pip
PIP_PROGRESS_BAR=off pip install -q -r requirements.txt

if [ "$DUET_ENGINE" = "magenta" ]; then
  magenta_requirements="requirements-magenta.txt"
  if [ -f "requirements-magenta-locked.txt" ]; then
    magenta_requirements="requirements-magenta-locked.txt"
  fi
  if [ -f "$magenta_requirements" ]; then
    echo "Installing Magenta requirements..."
    # Some pinned dependencies (e.g. apache-beam==2.40.0) fail under build isolation on newer setuptools
    # because `pkg_resources` was removed in setuptools v82. Use the venv's pinned setuptools instead.
    # Also prefer official PyPI to improve wheel availability across mirrors.
    PIP_PROGRESS_BAR=off pip install -q "setuptools<82" "setuptools_scm<10" wheel
    PIP_PROGRESS_BAR=off PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.org/simple}" \
      pip install -q --prefer-binary --no-build-isolation -r "$magenta_requirements"
  fi
fi

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
reply_notes_min_time="$(echo "$response" | python -c 'import json,sys; notes=json.loads(sys.stdin.read()).get("notes", []); print(min([float(n.get("time", 0.0)) for n in notes], default=0.0))')"
reply_notes_has_invalid="$(echo "$response" | python -c 'import json,sys; notes=json.loads(sys.stdin.read()).get("notes", []); bad=any(float(n.get("time",0.0))<0 or float(n.get("duration",0.0))<=0 for n in notes); print("1" if bad else "0")')"

if [ "${reply_notes_count}" -le 0 ]; then
  echo "generate failed: reply_notes_count<=0"
  echo "$response"
  echo "--- server log ---"
  tail -n 200 /tmp/piano_duet_server_smoke.log || true
  exit 1
fi

if [ "${reply_notes_has_invalid}" != "0" ]; then
  echo "generate failed: invalid time/duration in reply"
  echo "$response"
  exit 1
fi

if [ "${reply_notes_min_time}" != "0.0" ] && [ "${reply_notes_min_time}" != "0" ]; then
  echo "generate failed: min reply time != 0 (got ${reply_notes_min_time})"
  echo "$response"
  exit 1
fi

echo "generate ok reply_notes_count=${reply_notes_count}"

span_for_max_tokens() {
  local max_tokens="$1"
  local payload_local
  payload_local="$(echo "$payload" | python -c 'import json,sys; p=json.loads(sys.stdin.read()); p["params"]["max_tokens"]=int(sys.argv[1]); print(json.dumps(p))' "${max_tokens}")"
  local response_local
  response_local="$(curl -fsS -H 'Content-Type: application/json' -d "$payload_local" "${BASE_URL}/generate")"
  echo "$response_local" | python -c 'import json,sys; notes=json.loads(sys.stdin.read()).get("notes", []); end=max((float(n["time"])+float(n["duration"]) for n in notes), default=0.0); print(end)'
}

span_64="$(span_for_max_tokens 64)"
span_512="$(span_for_max_tokens 512)"

python - <<PY
span_64 = float("${span_64}")
span_512 = float("${span_512}")
if not (span_512 > span_64):
    raise SystemExit(f"max_tokens span check failed: span_64={span_64} span_512={span_512}")
print(f"span ok span_64={span_64} span_512={span_512}")
PY
