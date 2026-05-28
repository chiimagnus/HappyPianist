from __future__ import annotations

import argparse
import http.server
import socketserver
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ServerConfig:
    host: str
    port: int
    checkpoint: Path


class _Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"aria_server scaffold (P2-T1). Use POST /generate in P2.\n")

    def log_message(self, format: str, *args: object) -> None:  # noqa: A002
        # Keep the default HTTP server quiet; use explicit prints in main.
        return


def _default_checkpoint_path() -> Path:
    python_backend_dir = Path(__file__).resolve().parents[2]
    return python_backend_dir / "aria" / "hf" / "model-demo.safetensors"


def parse_args(argv: list[str] | None = None) -> ServerConfig:
    parser = argparse.ArgumentParser(prog="aria_server", add_help=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--checkpoint", type=Path, default=_default_checkpoint_path())
    args = parser.parse_args(argv)
    return ServerConfig(host=args.host, port=args.port, checkpoint=args.checkpoint)


def run(config: ServerConfig) -> None:
    service_type = "_lpduet._tcp"
    txt = {"path": "/generate", "protocol_version": "2", "engine": "aria", "engine_impl": "aria"}

    print(f"[aria_server] checkpoint={config.checkpoint}", flush=True)
    print(f"[aria_server] listening=http://{config.host}:{config.port}", flush=True)
    print(f"[aria_server] bonjour service_type={service_type} txt={txt}", flush=True)
    print("[aria_server] NOTE: scaffold only; /generate will be implemented in P2-T2.", flush=True)

    with socketserver.ThreadingTCPServer((config.host, config.port), _Handler) as httpd:
        httpd.serve_forever(poll_interval=0.2)


def main(argv: list[str] | None = None) -> None:
    config = parse_args(argv)
    run(config)


if __name__ == "__main__":
    main()
