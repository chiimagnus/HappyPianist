# Python 后端工作区

本目录是可选的本地服务/工具工作区，不是 AVP App 的运行依赖。当前网络后端只有 Aria v2（Bonjour + HTTP/WS）；AVP 默认仍可使用设备端 CoreML 或本地 rule 后端。模型源码在 `aria/`，服务工程在 `aria_server/`，入口和自检在 `scripts/`，共享协议在 `shared/`。

## 快速开始：运行 Aria v2 服务

前置条件：Python 3.11+ 和 `uv` 已安装；`python_backend/aria/hf/model-demo.safetensors` 已自行取得（权重不随仓库分发）。连接 Vision Pro 时，两台设备还需位于同一局域网。

1) 安装依赖（首次/更新后执行一次）
- `cd python_backend/aria_server && uv sync`

2) 启动服务（明确选择推理引擎，不自动回退）
- Apple 芯片：`cd python_backend && uv run --project aria_server python scripts/aria_server.py --engine mlx --host 0.0.0.0 --port 8766`
- NVIDIA CUDA：`cd python_backend && uv run --project aria_server python scripts/aria_server.py --engine cuda --host 0.0.0.0 --port 8766`

3) 本机自检（不依赖 AVP）
- HTTP：`cd python_backend && uv run --project aria_server python scripts/aria_server_smoketest.py --host 127.0.0.1 --port 8766`
- WebSocket：`cd python_backend && uv run --project aria_server python scripts/ws_client_smoketest.py ws://127.0.0.1:8766/stream`

4) 在 AVP 练习设置选择 `网络本地连接（Aria v2）`（HTTP `/generate`）或 streaming（WS `/stream`），并允许 Local Network 权限以发现 `_lpduet._tcp`。

## 故障排查

- 找不到服务：核对 `--host 0.0.0.0`、端口、防火墙和 `dns-sd -B _lpduet._tcp`。
- `checkpoint missing`：提供上述模型文件，或启动时传 `--checkpoint <path>`。
- `CUDA engine selected but torch.cuda is unavailable`：确认 NVIDIA 驱动及当前 PyTorch 构建可用 CUDA；服务不会自动切换到 MLX。

网络后端严格按用户选择运行；请求失败时 AVP 应提示并停止该次生成，不自动切换 provider。
