#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path


def _bootstrap_import_path() -> None:
    python_backend_dir = Path(__file__).resolve().parents[1]
    server_dir = python_backend_dir / "qwen_server"

    sys.path.insert(0, str(python_backend_dir))
    sys.path.insert(0, str(server_dir))


def main() -> None:
    _bootstrap_import_path()

    from qwen_server.server import main as server_main

    server_main()


if __name__ == "__main__":
    main()
