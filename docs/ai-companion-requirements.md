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

用户产生新输入后，未播放的旧 generation 必须失效；决策或生成失败时清理过期未来窗口，不能留下挂音，也不能改用另一个后端继续。

## 当前决策后端

### RuleBased

`RuleBasedCompanionDecisionBackend` 是默认基线。它行为确定、便于调试，负责证明上层实时控制链与模型无关。

### Qwen3.5-0.8B

后续实验先固定使用 `Qwen/Qwen3.5-0.8B`，不再维护并行实验后端。

Qwen 在电脑端本地运行，通过 Bonjour + `POST /v1/classifier` 被 visionOS 调用。服务使用 zero-token candidate logits，不生成解释文本。

产品不直接让 Qwen 做五分类，而是先判断四个二元语义：

- `continuing`：用户是否仍在继续当前乐句；
- `finished`：当前乐句是否已经明确结束；
- `space`：用户仍在演奏时是否有轻量陪奏空间；
- `reasserted`：AI 播放期间用户是否重新取得主导。

每个语义都做两次相同判断，只交换 `A/B` 中 true/false 的位置；对齐 true probability 后取平均，再通过固定 `semantic-v1` mapping 得到最终 `CompanionAction`。这样可以降低候选位置偏置。

输入只包含 compact structured state：按住音符数、踏板、IOI、力度趋势、近期音符密度、距最近用户事件/按键时间、音高中心和 AI 是否正在播放。逐音符 `recent_notes` 已删除，不应重新引入。

> **维护不变量：** Swift 产品后端与 Python benchmark 必须使用相同的四个语义、A/B 交换方式、阈值和 action mapping。修改其中一侧时，另一侧和对应测试必须在同一改动中更新。精确 wording、阈值和 mapping 以源码为真源，不在本文复制。

## 统一验证

模型比较只使用 `python_backend/scripts/companion_semantic_benchmark.py`：

- 同一 compact state；
- 同一四个二元语义；
- 同一 A/B 交换与概率聚合；
- 同一 action mapping；
- 同一固定 seed、case IDs、MAESTRO/POP909 corpus 与 Gate。

MAESTRO / POP909 没有“用户在等 AI”“AI 应该回应”等人工 turn-taking 标签，因此自然静默、踏板停顿等只能验证可观察边界和模型行为，不能包装成准确率。

截至 2026-09-26：

- Qwen 产品接入、client、backend selection 与失败不回退的定向测试：8/8 通过；
- `make build:simulator` 通过；
- 完整 Simulator suite：1010 通过、11 失败；失败集中在手部骨架、hand motion 与 local sampler，与 Qwen/Companion 无关；
- Qwen 固定 Stage A 仍不是全绿，密集演奏的语义分离和决策延迟仍需继续优化。

验证边界与完整测试证据见[测试](testing.md)。

## 接下来做什么

按这个顺序继续，不再同时探索多个模型：

1. **固定 Qwen 路线。** RuleBased 保留基线，Qwen 是唯一实验型网络决策后端。
2. **消除产品/benchmark 契约漂移风险。** 让 Swift 与 Python 的四个语义、A/B 顺序、阈值和 mapping 有一个可自动核对的真源或 fixture。
3. **继续同一 Stage A。** 只优化 Qwen 在现有统一协议下的剩余失败，不改样本和 Gate 来“过测试”。
4. **重跑当前协议的 Qwen → Aria → MIDI E2E。** 证明现在这套二元语义协议真的进入产品生成和播放链。
5. **再解决生成实时性。** Aria 目前仍偏向整段生成；真正的实时陪伴需要更短 generation latency 或真正的增量生成/播放。
6. **最后再加更高层音乐状态。** 只有现有 compact state 明确不足时，再加入节拍、和声、终止式或乐谱位置，不提前堆特征。

## 什么时候才换路线

只有固定 Qwen 协议经过上述验证仍无法达到关键语义和延迟 Gate，才进入下一层成本：先考虑 Qwen 的任务微调 / LoRA，再考虑专用音乐交互分类模型。全双工音乐模型属于更长期方向，不是当前任务。

## 相关文档

- [Python 后端](../python_backend/README.md)：Qwen / Aria 的安装、启动和 smoke。
- [数据流](data-flow.md)：输入、练习、AI 与持久化边界。
- [配置](configuration.md)：权限、网络与可选电脑端服务。
- [测试](testing.md)：自动化、Simulator、真机与证据边界。

研究参考保留少量直接相关项目： [ACCompanion](https://github.com/CPJKU/accompanion)、[Somax2](https://github.com/DYCI2/Somax2)、[Aria](https://github.com/EleutherAI/aria)、[Anticipatory Music Transformer](https://github.com/jthickstun/anticipation) 和 [Qwen3.5-0.8B](https://huggingface.co/Qwen/Qwen3.5-0.8B)。
