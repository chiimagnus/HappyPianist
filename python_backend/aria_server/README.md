# aria_server

LonelyPianist 的 **Mac 侧** Aria v2 本地服务（Bonjour + HTTP `/generate` + WebSocket `/stream`）。

## Quickstart

在仓库根目录执行：

1) 安装依赖（首次/更新后）
- `cd python_backend/aria_server && uv sync`

2) 启动服务（真机推荐监听全网卡）
- `cd python_backend && uv run --project aria_server python scripts/aria_server.py --host 0.0.0.0 --port 8766`

3) 自检
- HTTP：`cd python_backend && uv run --project aria_server python scripts/aria_server_smoketest.py --host 127.0.0.1 --port 8766`
- WS：`cd python_backend && uv run --project aria_server python scripts/ws_client_smoketest.py ws://127.0.0.1:8766/stream`

## Protocol / Discovery

- Bonjour service type：`_lpduet._tcp`
- TXT record（至少包含）：
  - `protocol_version=2`
  - `engine=aria`
  - `path=/generate`
  - `ws_path=/stream`

## Endpoints

- `GET /`：健康检查文本
- `POST /generate`：一次性返回 v2 events
- `GET /stream`：WebSocket，按时间窗推送 v2 chunks，最终 `is_final=true`

## Model checkpoint

默认从 `python_backend/aria/hf/model-demo.safetensors` 加载；可用 `--checkpoint <path>` 覆盖。
