#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}/../duet"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export PYTHONPATH="${REPO_ROOT}:${PYTHONPATH:-}"

# Default to Magenta for best musical quality.
# Users can override via `DUET_ENGINE=placeholder` etc.
DUET_ENGINE="${DUET_ENGINE:-magenta}"

# Default to writing debug bundles for quality tuning.
# Disable via `DUET_DEBUG=0` (or unset and export explicitly).
DUET_DEBUG="${DUET_DEBUG:-1}"
export DUET_DEBUG

VENV_DIR=".venv"
if [ "$DUET_ENGINE" = "magenta" ]; then
  VENV_DIR=".venv-magenta"
fi

PYTHON="${PYTHON:-}"
if [ -z "$PYTHON" ]; then
  if [ "$DUET_ENGINE" = "magenta" ]; then
    if command -v python3.9 >/dev/null 2>&1; then
      PYTHON="python3.9"
    else
      PYTHON="python3"
    fi
  else
    if command -v python3.10 >/dev/null 2>&1; then
      PYTHON="python3.10"
    elif command -v python3.12 >/dev/null 2>&1; then
      PYTHON="python3.12"
    else
      PYTHON="python3"
    fi
  fi
fi

if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "Error: $PYTHON not found. Install Python 3.10+ or run with: PYTHON=python3 python_backend/scripts/run_duet_server.sh" >&2
  exit 1
fi

if [ "${DUET_ENGINE:-placeholder}" = "magenta" ]; then
  py_ver="$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  if [ "$py_ver" != "3.9" ]; then
    echo "Error: DUET_ENGINE=magenta requires Python 3.9 (got ${py_ver})." >&2
    echo "Install python3.9 and run: PYTHON=python3.9 DUET_ENGINE=magenta python_backend/scripts/run_duet_server.sh" >&2
    exit 1
  fi
fi

desired_py_ver="$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [ -d "$VENV_DIR" ]; then
  expected_venv_path="$(pwd)/${VENV_DIR}"
  activate_path="${VENV_DIR}/bin/activate"
  if [ -f "$activate_path" ]; then
    declared_venv_path="$(rg -N '^VIRTUAL_ENV=' "$activate_path" | head -n 1 | sed -E 's/^VIRTUAL_ENV=//')"
    if [ -n "$declared_venv_path" ] && [ "$declared_venv_path" != "$expected_venv_path" ]; then
      echo "Existing ${VENV_DIR} was created at ${declared_venv_path}; recreating at ${expected_venv_path}..." >&2
      rm -rf "$VENV_DIR"
    fi
  fi

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

PORT="${PORT:-8766}"
exec python -m uvicorn api.main:app --host 0.0.0.0 --port "$PORT"
