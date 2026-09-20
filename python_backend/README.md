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

这个服务只判断“继续听 / 轻量陪奏 / 稀疏陪奏 / 让位 / 回应”，不负责生成音乐。默认使用官方 Qwen/Qwen3.5-0.8B，也可以通过 --model 指向后续微调后的本地 checkpoint。当前零样本模型只作为实验后端：600 个分层真实 MIDI 状态样本中只输出 respond / sparse，没有出现 listen / support / yield，默认仍使用确定性规则后端。

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

### 大规模真实 MIDI 验收

早期仓库只有 6 个 Aria 示例 MIDI，只适合作为 smoke test，不能代表真实陪伴决策。当前验收改用两个公开数据集；数据只保存在本地 python_backend/.datasets/，不提交 Git。

- MAESTRO v3 MIDI-only：1276 个真实 Disklavier 钢琴演奏 MIDI。官方 SHA256：70470ee253295c8d2c71e6d9d4a815189e35c89624b76d22fce5a019d5dde12c。
- POP909：909 首流行钢琴编曲主 MIDI，用于补足 MAESTRO 偏古典的风格分布。

本机当前共使用 2185 个主 MIDI。先建立状态候选索引：

- cd python_backend && python scripts/companion_acceptance_corpus.py --workers 8

脚本只从 MIDI 自身提取可观测状态，不再给每首曲子硬塞固定场景：

- active_dense：自然 MIDI，采样点前 1 秒至少 8 个 onset，且下一 onset 不超过 200 ms；
- active_sparse：自然 MIDI，采样点前 1 秒最多 4 个 onset，且下一 onset 约 50～550 ms；
- sustain_pause：自然 MIDI，真实 CC64 仍按下的停顿；
- natural_silence：自然 MIDI，无物理按键保持、踏板抬起的长停顿；
- piece_end：真实曲终边界；
- takeover_overlay：只把 AI 正在播放 叠加到真实 dense 用户片段上，明确属于合成交互状态，不冒充数据集真值。

索引器会再次校验每个候选的状态不变量；当前 2185/2185 个 MIDI 解析成功，0 错误。候选数量：active_dense=6255、active_sparse=6286、sustain_pause=6147、natural_silence=1474、piece_end=2185、takeover_overlay=6255。

这些是可观测状态候选，不是人工标注的 turn-taking 真值。自然静默可能是乐句内部休止，也可能是等待回应；曲终是否应该 respond 也属于产品策略。因此没有人工标签前，不应把它们直接计算成决策准确率。

只评估 Qwen 行为分布：

- cd python_backend && python scripts/companion_e2e_acceptance.py --decision-only --qwen-port 8767 --cases-per-state-per-source 50 --seed 20260920

当前分层抽样 600 个 case：Qwen 输出 respond=451、sparse=149，listen/support/yield=0；决策延迟中位数 135 ms（94～150 ms）。两个数据集上都存在同样的 respond 偏置。特别是显式合成的 takeover_overlay 中一次 yield 都没有，说明当前零样本模型还没有学会用户重新主导时让位。

完整服务级 E2E：

- cd python_backend && python scripts/companion_e2e_acceptance.py --qwen-port 8767 --aria-port 8766 --cases-per-state-per-source 5 --seed 20260920

当前分层抽样 60 个 case：真实 MIDI → Qwen /decision → Aria /generate → 输出 MIDI。最终完整运行中 60/60 生成成功，所有输出 MIDI 的 Note On / Note Off 配平；Qwen 决策中位数 133.5 ms，Aria 生成中位数 1535.5 ms，52/60（86.7%）在当前 0.45～0.70 秒实时播放窗口内至少有一个音符。

这仍然是服务级真实验收，不是 visionOS App 完整链路验收；Aria 生成具有随机性，后续还应做多次重复运行。

## 故障排查

- 找不到 Aria：核对 `--host 0.0.0.0`、端口、防火墙和 `dns-sd -B _lpduet._tcp`。
- `checkpoint missing`：提供 Aria 模型文件，或启动时传 `--checkpoint <path>`。
- `CUDA engine selected but torch.cuda is unavailable`：确认 NVIDIA 驱动及当前 PyTorch 构建可用 CUDA；Aria 不会自动切换到 MLX。
- Qwen 决策服务找不到：确认端口 8767、防火墙、同一局域网以及 `_lpduet._tcp` Bonjour 广播。
- Qwen CUDA 不可用：服务直接失败，不自动切换到 CPU，也不自动切回规则决策。

音乐生成后端与陪伴决策后端都严格按用户选择运行；请求失败时提示并停止本次处理，不自动切换 provider。
