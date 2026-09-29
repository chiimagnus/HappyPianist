# Python 后端工作区

本目录是可选的本地服务/工具工作区，不是 AVP App 的运行依赖。音乐生成可使用 Aria v2（Bonjour + HTTP/WS）；陪伴决策使用 Qwen3.5-0.8B zero-token typed classifier。AVP 的音乐生成与陪伴决策后端分别按用户选择运行，不自动回退。服务工程在 `aria_server/` 与 `qwen_server/`，入口和自检在 `scripts/`，共享协议在 `shared/`。

## 快速开始：运行 Aria v2 服务

前置条件：Python 3.11+ 和 `uv` 已安装；`python_backend/aria/hf/model-demo.safetensors` 已自行取得（权重不随仓库分发）。连接 Vision Pro 时，两台设备还需位于同一局域网。

权重来源：官方 `https://huggingface.co/loubb/aria-medium-base/resolve/main/model-demo.safetensors`。国内网络可用 HF Mirror 断点续传：`curl -L -C - -o aria/hf/model-demo.safetensors https://hf-mirror.com/loubb/aria-medium-base/resolve/main/model-demo.safetensors`。当前权重 SHA-256 为 `e747f107204e47d91f06d87c1830cfc90293be5bd7cd154e2ba1c7b4ef232d8b`。

1) 安装依赖（首次/更新后执行一次）
- `cd python_backend/aria_server && uv sync`

2) 启动服务（明确选择推理引擎，不自动回退）
- Apple 芯片：`cd python_backend && uv run --project aria_server python scripts/aria_server.py --engine mlx --host 0.0.0.0 --port 8766`
- NVIDIA CUDA：`cd python_backend && uv run --project aria_server python scripts/aria_server.py --engine cuda --host 0.0.0.0 --port 8766`

3) 本机自检（不依赖 AVP）
- HTTP：`cd python_backend && uv run --project aria_server python scripts/aria_server_smoketest.py --host 127.0.0.1 --port 8766`
- WebSocket：`cd python_backend && uv run --project aria_server python scripts/ws_client_smoketest.py ws://127.0.0.1:8766/stream`

4) 在 AVP 练习设置选择 `网络本地连接（Aria v2）`（HTTP `/generate`）或 streaming（WS `/stream`），并允许 Local Network 权限以发现 `_lpduet._tcp`。

## 快速开始：运行 Qwen3.5-0.8B 陪伴决策服务

陪伴决策服务固定使用 `Qwen/Qwen3.5-0.8B` + CUDA：模型不生成 completion，只读取 A/B 候选 token logits。四个二元语义、A/B 顺序消偏、概率聚合和 `semantic-v1` action mapping 全部由该服务统一拥有；visionOS、benchmark 与 E2E 不再复制这套逻辑。

1) 安装依赖（Windows + NVIDIA CUDA）
- `cd python_backend/qwen_server && uv sync`

2) 启动服务
- `cd python_backend && uv run --project qwen_server python scripts/qwen_server.py --host 0.0.0.0 --port 8767`
- model/device 不可配置：固定 `Qwen/Qwen3.5-0.8B` + CUDA；CUDA 不可用时服务直接失败，不自动切换 CPU/模型。

3) 本机自检
- `cd python_backend && uv run --project qwen_server python scripts/qwen_server_smoketest.py --host 127.0.0.1 --port 8767`

4) 在 AVP 的“即兴对弹”设置中明确选择 `Qwen3.5-0.8B（电脑本地，实验）`。服务通过 `_lpduet._tcp` 广播 `path=/v1/companion-decision`、`protocol_version=2`、`engine=qwen-companion`、`engine_impl=Qwen/Qwen3.5-0.8B`。请求只包含固定 compact state；协议/model identity 错误或请求失败都会显式失败，不会自动回退规则后端。

### 陪伴决策实验

统一 benchmark 位于 `scripts/companion_semantic_benchmark.py`，固定真源在 `tests/fixtures/companion_stage_a_manifest.json`。当前 projection 参数是 4s rolling history、2.4s IOI、1.2s density；MAESTRO / POP909 每个 state 各取 10 个不同文件，共 120 cases。runner 只允许改 host/port、dataset path 和 output，不允许临时改 seed/state/case 数或跳过 Gate。decision RTT P95 hard limit 固定 100ms。

## 故障排查

- 找不到 Aria：核对 `--host 0.0.0.0`、端口、防火墙和 `dns-sd -B _lpduet._tcp`。
- `checkpoint missing`：提供 Aria 模型文件，或启动时传 `--checkpoint <path>`。
- `CUDA engine selected but torch.cuda is unavailable`：确认 NVIDIA 驱动及当前 PyTorch 构建可用 CUDA；Aria 不会自动切换到 MLX。
- Qwen 陪伴决策服务找不到：确认 Windows 服务监听 `0.0.0.0:8767`、防火墙、同一局域网以及 `_lpduet._tcp` Bonjour 广播的专用 path/protocol/engine/model identity。
- Qwen CUDA 不可用：确认 NVIDIA 驱动及 qwen_server 的 PyTorch CUDA 构建；服务不会自动切换 CPU 或规则决策。

音乐生成后端与陪伴决策后端都严格按用户选择运行；请求失败时提示并停止本次处理，不自动切换 provider。
