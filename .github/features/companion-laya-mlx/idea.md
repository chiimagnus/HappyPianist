# Companion Laya-MLX 决策后端

## 背景 / 触发

当前 PR 先后尝试过 Qwen3.5 zero-token typed classifier、Prompt 分解和 CLM System One。Qwen 路线暴露二元候选顺序偏置，CLM 需要 8B encoder 且 synthetic 边界仍不稳定。用户已明确 pivot：后续只在 Mac 开发，决策模型改为原生 Apple Silicon 的 Laya-MLX，不再继续 Qwen 或 CLM。

Laya 原生提供 `choice / score / noul` typed decisions、校准概率和 `output_tokens=0`，`laya-mlx` 可直接在 Apple Silicon 上运行。默认使用更小、更快的 `aac6fef/laya-multilingual-mlx`（322M）。

## 核心需求

1. Mac 本机直接运行 Laya-MLX 决策服务；不依赖 Windows、CUDA、PyTorch 或 Transformers runtime。
2. Python 服务保持最小 HTTP typed-decision 边界：`state + questions -> answers + usage`，默认模型为 `aac6fef/laya-multilingual-mlx`。
3. 服务启动时完成模型加载；首个产品请求不能承担模型下载/加载成本。
4. visionOS 端产品命名、设置项、Bonjour TXT record、Swift client/backend 全部改为 Laya，不再暴露 Jev/Qwen/CLM 名称。
5. Companion 决策直接使用 Laya 的 `choice` 输出映射 `listen / support / sparse / yield / respond`，不保留 Qwen 专用 semantic decomposition 或标签顺序消偏逻辑。
6. Laya 服务不可用、协议错误或模型响应非法时显式失败；不得静默回退规则后端。
7. RuleBased 后端继续作为稳定基线和默认选择；Laya 为明确可选的本地 AI 决策后端。
8. 保留与模型无关的真实 MIDI corpus/状态生成能力；重写 benchmark，只验证 Laya 在固定边界上的行为与延迟，不宣称没有人工标签的 accuracy。
9. Aria 音乐生成链保持不变；Laya 只负责 companion action decision。
10. 新实现落地时删除当前 PR 中的 Qwen、CLM、Jev runtime、旧 Prompt benchmark、旧文档和兼容双轨。

## 默认值与兼容策略

- Laya checkpoint 默认：`aac6fef/laya-multilingual-mlx`。
- Companion decision 默认仍为 `ruleBased`；用户选择 Laya 后严格使用 Laya。
- 当前 AI 决策功能尚未发布，不保留 `network_bonjour_jev` 等开发期 raw value 兼容层，直接改为 Laya 命名。

## 非目标

- 不继续 Qwen/Jev logits scorer、Prompt-only 优化或候选顺序消偏。
- 不继续 CLM、projection head 或 CLM finetune。
- 不微调 Laya，不引入新的训练流水线。
- 不改变 Aria 模型、生成策略或 MIDI 播放架构。
- 不为 Windows GPU 后端保留第二套运行路径。

## 验收标准

- Mac Apple Silicon 上 Laya-MLX 服务可从冷启动完成模型加载，并通过真实 `choice` smoke；响应 `output_tokens=0`。
- App 的 Laya Bonjour discovery -> Swift HTTP client -> companion backend -> `AIPerformanceService` 调用链可达。
- 固定 MIDI 状态 benchmark 可重复运行，输出 action 分布、关键边界和热态延迟；无 silent failure/collapse 时才作为当前实验后端保留。
- `make build:simulator` 与 `make test:simulator` 通过。
- PR 最终产品代码、Python runtime、测试与长期文档不存在 Qwen、CLM 或 Jev 决策实现残留；仅 Git 历史不在扫描范围。
