#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "pydantic>=2",
#   "zeroconf",
#   "mido",
#   "safetensors",
# ]
# ///
from __future__ import annotations

import sys
from pathlib import Path


def _bootstrap_import_path() -> None:
    python_backend_dir = Path(__file__).resolve().parents[1]
    aria_server_dir = python_backend_dir / "aria_server"
    aria_dir = python_backend_dir / "aria"
    shared_dir = python_backend_dir

    sys.path.insert(0, str(aria_server_dir))
    sys.path.insert(0, str(aria_dir))
    sys.path.insert(0, str(shared_dir))


def main() -> None:
    _bootstrap_import_path()

    from aria_server.server import main as server_main

    server_main()


if __name__ == "__main__":
    main()
