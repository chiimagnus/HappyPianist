# AI 陪伴

HappyPianist 的目标不是“生成一段音乐”，而是让 AI 在用户演奏时成为可控、可打断、会让位的钢琴搭档。

用户关心的是 **AI 要做什么**；模型只是实现细节。音乐生成后端与陪伴决策后端独立选择，用户选定后，失败必须显式暴露，不能静默切换实现。

## 产品关系

| 关系 | HappyPianist 负责 | 生成/演奏能力 |
| --- | --- | --- |
| 陪你弹 | 持续监听、决定加入/让位、控制重叠和密度 | 实时伴奏或短窗口生成 |
| 和你对话 | 判断乐句结束、触发回应、用户重新进入时打断 AI | Aria 等续奏模型 |
| 跟着你变 | 跟踪速度、力度、节拍和乐谱位置 | 跟随算法 + 可控生成 |
| 替你补全 | 明确要补的手、声部、小节和约束 | 受约束 MIDI 补全模型 |
| 陪你练 | 根据练习、评估、指导和复测决定 AI 如何参与 | 现有练习系统为主 |
| 给你示范 | 决定示范范围、手别、速度和表现方式 | 优先确定性乐谱播放，必要时再生成 |

六种关系共享同一实时陪伴底座，不为每种关系复制一套系统。

## 当前数据流

```text
用户 MIDI / 踏板 / 当前乐谱
→ 实时演奏状态
→ CompanionDecisionBackendProtocol
→ CompanionAction
→ DuetPhrasePolicy
→ 生成短窗口
→ 播放队列
```

当前决策动作只有五种：`listen / support / sparse / yield / respond`。生成窗口、请求频率、token 数和播放调度不属于决策模型，由 HappyPianist 自己控制。

播放生命周期只有 `idle / preparing / playing` 一个真源。`preparing` 期间 UI 仍显示 AI 正在处理，但 Companion 的 `is_ai_playback_active` 只有在真实 `service.play()` 成功后才为 true。每次进入 `playing` 都重置“播放开始后用户是否新按键”；只有用户来源的新 note-on 能重新置 true，note-off 和 system playback 都不能。

用户产生新输入后，旧 generation、pending window 和尚未开始的 preparation 必须失效，但已经开始发声的当前短窗口不能被输入事件直接停止。`listen` 只清未开始窗口；`support / sparse / respond` 保留当前播放并可继续生成；只有 `yield` 会立即停止当前播放并清未来窗口。所有 backend 的 `yield` 都必须满足“AI 正在真实播放 + 本轮播放开始后用户出现新 note-on”。

## 当前决策后端

### RuleBased

`RuleBasedCompanionDecisionBackend` 是默认基线。它行为确定、便于调试，负责证明上层实时控制链与模型无关。

### Qwen3.5-0.8B

后续实验先固定使用 `Qwen/Qwen3.5-0.8B`，不再维护并行实验后端。

Qwen 在 Windows + NVIDIA CUDA 电脑端本地运行，通过 Bonjour + `POST /v1/companion-decision` 被 visionOS 调用。服务固定加载 `Qwen/Qwen3.5-0.8B`，使用 zero-token A/B candidate logits，不生成解释文本。

产品不直接让 Qwen 做五分类，而是先判断四个二元语义：

- `continuing`：用户是否仍在继续当前乐句；
- `finished`：当前乐句是否已经明确结束；
- `space`：用户仍在演奏时是否有轻量陪奏空间；
- `reasserted`：AI 播放期间用户是否重新取得主导。

每个语义都做两次相同判断，只交换 `A/B` 中 true/false 的位置；对齐 true probability 后取平均，再通过固定 `semantic-v1` mapping 得到最终 `CompanionAction`。这样可以降低候选位置偏置。

Qwen 网络请求只包含决策真正使用的 compact state：按住音符数、踏板、IOI、近期音符密度、距最近一次 note-on 的时间、AI 是否正在播放，以及 AI 开始播放后用户是否出现新的 note-on。RuleBased 或后续生成 policy 专用字段不发送给 Qwen。逐音符 `recent_notes` 不应进入 Qwen 网络协议。

> **维护不变量：** 四个语义、A/B 交换、阈值和 `semantic-v1` mapping 只有 Python Qwen Companion service 一个 runtime owner。Swift 产品、benchmark 和 E2E 都消费该服务返回的 action/scores，不再各自复制 semantic contract。

## 统一验证

模型比较只使用 `python_backend/scripts/companion_semantic_benchmark.py`。Stage A 由版本化 manifest 固定：

- Qwen state projection 与产品一致：4s rolling history、2.4s IOI、1.2s density，并按原始 MIDI 事件顺序重放 CC64/held-note 生命周期；
- MAESTRO / POP909 × 6 states，每个 source/state 固定 10 个不同文件，共 120 cases；
- 固定 Qwen Companion protocol、四个二元语义、A/B 消偏、`semantic-v1` mapping 与 0.55 threshold；
- 每个 source 单独检查 observable semantic boundary，不拿 MAESTRO/POP909 的 median 互相当真值；
- decision RTT P95 hard Gate 固定为 100ms，与产品 100ms control-loop target 对齐；runner 没有 `--no-gate` 或可临时改 seed/state/case 数的入口。

MAESTRO / POP909 没有“用户在等 AI”“AI 应该回应”等人工 turn-taking 标签，因此自然静默、踏板停顿等只能验证可观察边界和模型行为，不能包装成准确率。

截至 2026-09-29：

- P0 架构收敛已完成：decision identity 绑定 activation / phrase generation / playback phase / post-start note-on / backend selection；stale decision 静默丢弃；
- Companion control loop 固定 100ms hard deadline；Qwen Bonjour discovery/state fail-fast，Swift client 只消费剩余预算；Python Qwen runtime 为 single-flight，重叠请求立即 `503 busy`；
- T7 Swift 定向回归 13/13 通过，其中 hard-deadline 用例 0.115s 完成；Python Qwen server + semantic benchmark 17/17 通过；
- Swift/Python state-projection golden parity 已通过；Stage A corpus/manifest 已按产品 projection 重建；
- `make build:simulator` 已通过；完整 Simulator suite 复跑为 1018 passed / 11 failed / 0 skipped，11 个失败均与 P0 前基线一致，集中在 hand motion/rig、local sampler 与 demonstration hands；Companion/AIPerformance 无新增失败；
- 正式 Qwen 模型 Gate 留给后续固定 Stage A 执行。

验证边界与完整测试证据见[测试](testing.md)。

## 接下来做什么

按这个顺序继续，不再同时探索多个模型：

1. **重建固定 Stage A baseline。** 只使用已冻结 manifest/协议，在 Windows RTX 4060 + Qwen CUDA service 上完成可重复双跑。
2. **定位 Qwen 决策时延和 Prompt 冗余。** 先用 timing 证据拆 render/tokenize/tensor/GPU/decode/HTTP，再决定是否精简。
3. **用同一 Stage A 收口 Qwen Gate。** 不改样本、不改 100ms Gate 来“过测试”。
4. **重跑当前协议的 Qwen → Aria → MIDI E2E。** 证明当前决策协议真的进入产品生成和播放链。
5. **再解决生成实时性。** Aria 目前仍偏向整段生成；真正的实时陪伴需要更短 generation latency 或真正的增量生成/播放。

## 什么时候才换路线

只有固定 Qwen 协议经过上述验证仍无法达到关键语义和延迟 Gate，才进入下一层成本：先考虑 Qwen 的任务微调 / LoRA，再考虑专用音乐交互分类模型。全双工音乐模型属于更长期方向，不是当前任务。

## 相关文档

- [Python 后端](../python_backend/README.md)：Qwen / Aria 的安装、启动和 smoke。
- [数据流](data-flow.md)：输入、练习、AI 与持久化边界。
- [配置](configuration.md)：权限、网络与可选电脑端服务。
- [测试](testing.md)：自动化、Simulator、真机与证据边界。

研究参考保留少量直接相关项目： [ACCompanion](https://github.com/CPJKU/accompanion)、[Somax2](https://github.com/DYCI2/Somax2)、[Aria](https://github.com/EleutherAI/aria)、[Anticipatory Music Transformer](https://github.com/jthickstun/anticipation) 和 [Qwen3.5-0.8B](https://huggingface.co/Qwen/Qwen3.5-0.8B)。
