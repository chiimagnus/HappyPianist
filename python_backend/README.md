# Python 后端工作区

本目录是可选的本地服务/工具工作区，不是 AVP App 的运行依赖。音乐生成可使用 Aria v2（Bonjour + HTTP/WS）；实时陪伴决策可使用独立的 Qwen3.5 本地服务。AVP 仍可分别选择设备端/规则实现，两类后端互相独立，不自动回退。模型源码在 `aria/`，服务工程在 `aria_server/` 与 `companion_decision_server/`，入口和自检在 `scripts/`，共享协议在 `shared/`。

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

## 快速开始：运行 Qwen3.5 陪伴决策服务

这个服务只判断“继续听 / 轻量陪奏 / 稀疏陪奏 / 让位 / 回应”，不负责生成音乐。默认使用官方 `Qwen/Qwen3.5-0.8B`，也可以通过 `--model` 指向后续微调后的本地 checkpoint。当前零样本模型只作为**实验后端**：真实 MIDI 验收中决策语义通过率仅 7/30，默认仍使用确定性规则后端。

1) 安装依赖（首次/更新后执行一次）
- `cd python_backend/companion_decision_server && uv sync`

2) 启动服务
- NVIDIA CUDA：`cd python_backend && uv run --project companion_decision_server python scripts/companion_decision_server.py --device cuda --host 0.0.0.0 --port 8767`
- CPU：把 `--device cuda` 改成 `--device cpu`；服务不会在 CUDA 失败时自动切换。
- 已下载或微调的模型：追加 `--model <模型目录>`。

3) 本机自检
- `cd python_backend && python scripts/companion_decision_smoketest.py --host 127.0.0.1 --port 8767`

4) 在 AVP 的“即兴对弹”设置中，把“陪伴决策后端”明确选择为 `Qwen3.5-0.8B（电脑本地，实验）`。音乐生成后端仍单独选择 Aria / CoreML / rule。

服务启动时会加载并预热模型；`/decision` 只做一次前向传播并返回动作、置信度和完整概率分布。未来替换 LoRA/任务微调 checkpoint 时，上层协议不需要修改。

### 真实 MIDI 端到端验收

同时启动 Qwen 决策服务和 Aria 服务后，可运行：

- `cd python_backend && python scripts/companion_e2e_acceptance.py --qwen-port 8767 --aria-port 8766`

脚本直接使用 `aria/example-prompts/` 中 6 个真实 MIDI，每首构造持续演奏、乐句结束、延音停顿、用户重新接管、静默 5 种状态，共 30 个场景。链路为：真实 MIDI → Qwen `/decision` → Aria `/generate` → 输出 MIDI；结果写到 `python_backend/.outputs/companion-decision-e2e/`。

2026-09-20 当前结果：30/30 场景完成技术链路并生成 MIDI，但 Qwen 决策语义只通过 7/30；生成结果中 20/30 在当前实时播放窗口内至少有一个音符。因此该脚本是**服务级真实验收**，不是 visionOS App 完整链路验收。

## 故障排查

- 找不到 Aria：核对 `--host 0.0.0.0`、端口、防火墙和 `dns-sd -B _lpduet._tcp`。
- `checkpoint missing`：提供 Aria 模型文件，或启动时传 `--checkpoint <path>`。
- `CUDA engine selected but torch.cuda is unavailable`：确认 NVIDIA 驱动及当前 PyTorch 构建可用 CUDA；Aria 不会自动切换到 MLX。
- Qwen 决策服务找不到：确认端口 8767、防火墙、同一局域网以及 `_lpduet._tcp` Bonjour 广播。
- Qwen CUDA 不可用：服务直接失败，不自动切换到 CPU，也不自动切回规则决策。

音乐生成后端与陪伴决策后端都严格按用户选择运行；请求失败时提示并停止本次处理，不自动切换 provider。
