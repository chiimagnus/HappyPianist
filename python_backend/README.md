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

## 快速开始：运行 Qwen3.5-0.8B 分类服务

陪伴决策使用 `Qwen/Qwen3.5-0.8B` 的 zero-token choice 分类：模型不生成 completion，只读取候选 token logits。当前产品协议固定为 4 个二元语义判断，并把语义 true 分别放在 A/B 两个位置后对齐求平均，再通过同一 `semantic-v1` 规则映射到 `listen / support / sparse / yield / respond`。

1) 安装依赖（Windows + NVIDIA CUDA）
- `cd python_backend/qwen_server && uv sync`

2) 启动服务
- `cd python_backend && uv run --project qwen_server python scripts/qwen_server.py --device cuda --host 0.0.0.0 --port 8767`
- 默认模型是 `Qwen/Qwen3.5-0.8B`；CUDA 不可用时服务直接失败，不自动切换 CPU。

3) 本机自检
- `cd python_backend && uv run --project qwen_server python scripts/qwen_server_smoketest.py --host 127.0.0.1 --port 8767`

4) 在 AVP 的“即兴对弹”设置中明确选择 `Qwen3.5-0.8B（电脑本地，实验）`。服务通过 `_lpduet._tcp` 广播 `path=/v1/classifier`、`protocol_version=1`、`engine=qwen-classifier` 与实际 `engine_impl`。协议错误、模型错误或请求失败都会显式失败，不会自动回退规则后端。

### 陪伴决策实验

统一 benchmark 位于 `scripts/companion_semantic_benchmark.py`。不同模型必须使用同一 compact state、同一 4 个二元问题、同一 A/B 顺序消偏、同一阈值、同一 mapping、同一 120-case Stage A；不能为模型单独改口径。

## 故障排查

- 找不到 Aria：核对 `--host 0.0.0.0`、端口、防火墙和 `dns-sd -B _lpduet._tcp`。
- `checkpoint missing`：提供 Aria 模型文件，或启动时传 `--checkpoint <path>`。
- `CUDA engine selected but torch.cuda is unavailable`：确认 NVIDIA 驱动及当前 PyTorch 构建可用 CUDA；Aria 不会自动切换到 MLX。
- Qwen 分类服务找不到：确认 Windows 服务监听 `0.0.0.0:8767`、防火墙、同一局域网以及 `_lpduet._tcp` Bonjour 广播。
- Qwen CUDA 不可用：确认 NVIDIA 驱动及 qwen_server 的 PyTorch CUDA 构建；服务不会自动切换 CPU 或规则决策。

音乐生成后端与陪伴决策后端都严格按用户选择运行；请求失败时提示并停止本次处理，不自动切换 provider。
