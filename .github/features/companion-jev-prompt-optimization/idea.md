# Companion Jev-like 决策与 Prompt 优化

## 背景 / 触发

HappyPianist 的实时陪伴底座已经把“什么时候参与”与“生成什么音乐”拆开：AIPerformanceService 通过 CompanionDecisionBackendProtocol 获取 listen / support / sparse / yield / respond，再由 DuetPhrasePolicy 决定生成窗口与播放策略。

最初的 Qwen3.5-0.8B 实验后端是钢琴专用 scorer：Python 服务写死钢琴状态、A/B/C/D/E 标签和 /decision 协议。真实 MIDI 批量测试随后暴露两个问题：专用 scorer 与业务强耦合；直接五选一 logits 对候选 token/顺序敏感，并可能出现 action collapse。

用户当前决定是：先完成通用 Jev-like 架构，再系统验证仅靠 Prompt 是否足够改善 Qwen3.5-0.8B。本 feature 暂不进入模型微调。当前工作区已有未提交的 Jev runtime、Swift client、Prompt benchmark 和真实 MIDI 验收草稿；计划从这些真实改动继续收敛，不另起并行实现。

## 核心需求（原始需求精炼）

1. Python 决策服务改为领域无关的 Jev-like typed classifier：输入 model + state + questions；至少支持 choice 和 noul；只读取 answer-boundary logits；返回 typed JSON，output_tokens = 0。
2. 钢琴语义只能存在于 companion adapter / prompt schema 层；Jev runtime 和通用 Swift transport 不得写死 listen / support / yield / respond。
3. 旧 /decision、companion_decision_server、decision_protocol.py 和旧 Swift Qwen client 被替代后删除；不保留兼容 fallback 或双轨实现。
4. Prompt 优化必须固定模型、语料和抽样 seed；改变 Prompt 时不得同时改变样本或动作映射。
5. Prompt 至少比较 direct、observable、explicit boundaries/thresholds、examples、conservative 等真正不同策略，不能只做同义改写。
6. 为避免五选一标签顺序偏置，允许把动作拆成 continuing / finished / space / reasserted 等独立语义 Noul，再由确定性映射得到动作；映射必须可测试、不可依赖文本解析。
7. 继续使用 MAESTRO v3 1276 主 MIDI + POP909 909 主 MIDI。数据位于 python_backend/.datasets/，不得提交 Git；takeover_overlay 必须标为 synthetic；无人工 turn-taking 真值的自然状态只能报告行为分布，不能伪装成准确率。
8. Prompt 筛选两阶段：Stage A 小样本分层筛选；Stage B 只对 Stage A 候选运行固定 600-case（2 来源 × 6 状态 × 50）。
9. 评价必须分别报告各状态 action/semantic score 分布、takeover 的 yield/reasserted、dense 的 finished/respond、sustain pause 的 continuing/finished、跨来源一致性、延迟和 collapse，不压成单一主观总分。
10. 只有经 P2 实验证据支持的 semantic schema / Prompt 才能接入正式 JevNetworkCompanionDecisionBackend；benchmark 与产品不能用两套逻辑。
11. Jev 失败时显式失败，不得自动切回规则；RuleBasedCompanionDecisionBackend 仍是默认稳定基线。
12. 最终验证真实服务链：MIDI -> companion state -> Jev/Qwen -> CompanionDecision -> Aria -> MIDI，并记录生成失败、NoteEvent、Note On/Off 配平、实时播放窗口和延迟。

## 默认值与兼容策略

- 默认仍使用 RuleBasedCompanionDecisionBackend；Jev/Qwen 保持实验选项。
- Jev 只使用 /v1/classifier；旧 /decision 不兼容、不兜底。
- listen / support / sparse / yield / respond 仍是业务动作；生成参数继续由 DuetPhrasePolicy 拥有。
- MAESTRO / POP909 和 .outputs/ 都只作为本地实验资产，不入库。
- 如果 Prompt-only 没有稳定改善，允许结论为“仅靠 Prompt 暂不足”，不得强行选 winner。

## 非目标

- 不做 Qwen LoRA / SFT / 参数微调。
- 不训练新的 MIDI Transformer 或音乐生成模型。
- 不替换 Aria。
- 不实现真实双人数据采集。
- 不为无人工标签数据虚构 ground truth。
- 不完整照搬 Jev Web UI、批处理平台或当前未用能力。
- 不保留旧 scorer 兼容层。

## 验收标准

- 通用 Jev runtime 可用完全非钢琴问题真实调用 Qwen3.5-0.8B，并返回 typed answer、output_tokens=0。
- choice/noul prompt 编译、single-token candidate 边界、错误路径和 response schema 有回归测试。
- 全仓没有旧 /decision、companion_decision_server、decision_protocol.py 或旧 Swift Qwen client 的生产引用。
- 2185 首 MIDI 候选索引可重复生成且状态不变量通过。
- Stage A 与 Stage B 均使用固定 case IDs；实验结论可复现。
- Swift JevClassifierClient 只承载通用协议；JevNetworkCompanionDecisionBackend 与最终实验 schema/action mapping 一致。
- 服务级 E2E 能整批运行，单 case 失败只记录不提前中止。
- Python 回归、uv lock --check、git diff --check、CodeGraph sync 通过；macOS/Xcode 可用时再执行 Swift build/test，环境不可用时明确记录。
