# python_backend/scripts

本目录用于放置 **可运行的** Python 服务/工具入口脚本（例如 `run_<service>.sh`、`smoke_<service>.sh`）。

当前仓库没有内置可运行的 Duet（A.I. Duet）Python 服务；AI 即兴使用 AVP 端的本地 CoreML / 本地 rule 后端。

## Aria v2

- 启动（先做骨架，路由逻辑在后续 tasks）：`uv run python scripts/aria_server.py --help`
