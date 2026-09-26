# Python 后端工作区

本目录是可选的本地服务/工具工作区，不是 AVP App 的运行依赖。音乐生成可使用 Aria v2（Bonjour + HTTP/WS）；陪伴决策使用 Apple Silicon 本机的 Laya-MLX typed classifier。AVP 的音乐生成与陪伴决策后端分别按用户选择运行，不自动回退。模型源码在 `aria/`，服务工程在 `aria_server/` 与 `laya_server/`，入口和自检在 `scripts/`，共享协议在 `shared/`。

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

## 快速开始：运行 Laya-MLX 分类服务

Laya-MLX 是 Apple Silicon 本机的 System One typed decision runtime，支持 `choice`、`score` 与 `noul`，不生成 completion 文本。默认 checkpoint 是 `aac6fef/laya-multilingual-mlx`（322M）。

1) 安装依赖（首次/更新后执行一次）
- `cd python_backend/laya_server && uv sync --python 3.12`

2) 启动服务
- `cd python_backend && uv run --project laya_server --python 3.12 python scripts/laya_server.py --host 0.0.0.0 --port 8767`
- 首次启动需要从 Hugging Face 下载 checkpoint；模型加载完成后服务才开始监听，不会把冷加载成本塞进首个产品请求。
- 如需实验其他兼容 Laya checkpoint，可显式追加 `--model <模型目录或 Hugging Face model id>`；服务不会自动切换模型。

3) 本机自检
- `cd python_backend && uv run --project laya_server --python 3.12 python scripts/laya_server_smoketest.py --host 127.0.0.1 --port 8767`

smoke 使用非音乐问题调用 `POST /v1/classifier`，并要求 typed answer 正确且 `output_tokens=0`。

4) 在 AVP 的“即兴对弹”设置中，把“陪伴决策后端”明确选择为 Laya 分类器。钢琴状态到五种动作的语义只存在于 companion adapter；音乐生成后端仍单独选择 Aria / CoreML / rule。

服务通过 `_lpduet._tcp` 广播 `path=/v1/classifier`、`protocol_version=1`、`engine=laya-mlx` 与实际 `engine_impl`。分类、schema 或模型错误都会显式失败，不会伪造答案或自动切回规则后端。

### 陪伴决策实验

Laya runtime 的 smoke 只验证通用 typed-decision 协议与 0-output-token 推理，不代表钢琴陪伴行为已经达到产品质量。真实 MIDI corpus、固定边界 benchmark 与端到端音乐生成验收属于独立实验流程；验证边界记录在 `docs/ai-companion-requirements.md`。

## 故障排查

- 找不到 Aria：核对 `--host 0.0.0.0`、端口、防火墙和 `dns-sd -B _lpduet._tcp`。
- `checkpoint missing`：提供 Aria 模型文件，或启动时传 `--checkpoint <path>`。
- `CUDA engine selected but torch.cuda is unavailable`：确认 NVIDIA 驱动及当前 PyTorch 构建可用 CUDA；Aria 不会自动切换到 MLX。
- Laya 分类服务找不到：确认端口 8767、防火墙、同一局域网以及 `_lpduet._tcp` Bonjour 广播。
- Laya checkpoint 下载或加载失败：服务直接失败，不自动切换其他模型，也不自动切回规则决策。

音乐生成后端与陪伴决策后端都严格按用户选择运行；请求失败时提示并停止本次处理，不自动切换 provider。
