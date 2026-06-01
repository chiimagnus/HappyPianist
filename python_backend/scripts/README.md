# python_backend/scripts

本目录用于放置 **可运行的** Python 服务/工具入口脚本（例如 `run_<service>.sh`、`smoke_<service>.sh`）。

当前仓库没有内置可运行的 Duet（A.I. Duet / Performance RNN）Python 服务；A.I. Duet 默认在 **AVP 端本地 CoreML** 跑。

## Aria v2

- 帮助：`uv run --project aria_server python scripts/aria_server.py --help`
- 启动（真机推荐）：`uv run --project aria_server python scripts/aria_server.py --host 0.0.0.0 --port 8766`
- HTTP smoketest：`uv run --project aria_server python scripts/aria_server_smoketest.py --host 127.0.0.1 --port 8766`
- WS smoketest：`uv run --project aria_server python scripts/ws_client_smoketest.py ws://127.0.0.1:8766/stream`
