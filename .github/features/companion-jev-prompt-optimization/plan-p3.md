# Plan P3 - 产品决策适配与真实 E2E

**Goal:** 让 Swift 正式 Jev companion backend 与 P2 选定的 semantic schema / Prompt 完全一致，并证明真实 MIDI 可走通 Jev 决策、Aria 生成和 MIDI 输出。

**Non-goals:** 不把 Jev 改成默认后端；不改变 Aria 模型；不微调 Qwen。

**Approach:** 先把 P2 的 schema 作为业务真源迁移到 Swift adapter，避免 benchmark 和产品各写一套。随后在固定分层样本上做真实服务级 E2E，把决策延迟、生成延迟、MIDI 合法性和实时窗口分别验收。

**Acceptance:**
- Swift JevNetworkCompanionDecisionBackend 使用与 P2 一致的 semantic questions、score interpretation 和 action mapping。
- Jev failure 明确上报，不回退 rule backend。
- 真实 E2E 整批运行不因单 case 失败提前终止。
- 输出 MIDI 可重新解析，失败类型和实时窗口结果可统计。

**Rules:**
- 若 P2 结论是 Prompt-only 无合格方案，不把失败 profile 强行提升为产品逻辑；只保留通用 Jev 实验路径。
- DuetPhrasePolicy 继续拥有 generation window/token 参数，Jev 只输出语义动作。

---

## P3-T1 让 Swift companion adapter 与实验真源一致

**Files:**
- Modify: HappyPianistAVP/Services/Practice/AI/TurnTaking/JevNetworkCompanionDecisionBackend.swift
- Modify/Add: HappyPianistAVPTests 中 companion Jev backend 对应测试

**Current evidence / root issue:**
- CodeGraph 当前显示正式 Swift adapter 仍用单个 JevChoiceQuestion 五选一，而 Python benchmark 已在尝试 semantic Noul decomposition；两者存在漂移风险。

**Step 1: 复用 P2 结论**

把最终 question schema / state formatting / deterministic action mapping 以最小职责方式落到 Swift companion adapter；通用 Jev client 不复制业务语义。

**Step 2: 错误边界**

缺 answer、非法 score、未知 action、discovery/model identity 失败均显式报错；不调用 rule fallback。

**Step 3: 单测**

覆盖 dense active、sustain pause、takeover while AI playback、settled end/natural silence 的已定义边界，以及 malformed response。

**Step 4: 原子提交**

只提交 companion adapter 与对应测试。

---

## P3-T2 运行固定分层 Qwen -> Aria -> MIDI E2E

**Files:**
- Modify: python_backend/scripts/companion_e2e_acceptance.py
- Reuse: python_backend/scripts/companion_acceptance_corpus.py

**Step 1: 固定样本**

至少每来源 × 每状态 × 5 = 60 case，使用固定 seed；必须使用 P2 选定的 profile/schema。

**Step 2: 完整服务链**

真实调用 /v1/classifier 与 Aria /generate，并把结果写成 MIDI。

**Step 3: 单 case 容错**

分类或生成失败记录到 case result 后继续；汇总区分 HTTP/runtime failure、无 NoteEvent、实时窗口无音符等失败。

**Step 4: 验证输出**

统计 Jev action/semantic scores、classifier latency、Aria latency、generated note/event count、Note On/Off 配平、playback horizon 内可播放 NoteEvent 和 generation failures。

**Step 5: 随机性说明**

Aria 有采样随机性；对边缘异常做有限重复确认，不通过无限重跑挑好结果。

---

## P3-T3 核对实时控制环接入与失败行为

**Files:**
- Inspect/Modify as required: HappyPianistAVP/Services/Practice/AI/AIPerformanceService.swift
- Inspect: HappyPianistAVP/Services/Practice/AI/TurnTaking/DuetPhrasePolicy.swift
- Inspect: HappyPianistAVP/Services/Practice/AI/Playback/DuetAIPlaybackQueue.swift（以真实路径为准）

**Step 1: 调用链核对**

从 AIPerformanceService.requestCompanionDecision 追到 Jev backend、generation request、policy、playback queue，确认新 semantic path 真正参与运行。

**Step 2: 延迟与取消**

确认 classifier 延迟不会再叠加固定 100ms sleep；新用户输入仍可取消/清理过时生成和播放窗口。

**Step 3: 失败行为**

Jev 超时/失败停止该次决策并可见报告，不静默切换规则。

**Step 4: 针对性验证**

优先复用现有 service tests；只有机器测试无法证明的行为才安排 simulator/device 实验。

**Step 5: 原子提交**

只提交控制环必要修正；若审查证明无需改代码，不制造空提交，在 todo note 记录证据。

---

## Phase Audit

- Audit file: audit-p3.md
- Rule: 完成本 phase 全部 tasks 后，executing-plans 必须自动进入该文件的审计闭环
