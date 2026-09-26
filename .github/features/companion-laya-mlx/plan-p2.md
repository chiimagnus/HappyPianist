# Plan P2 - Laya 产品接入与固定边界验证

**Goal:** 把 visionOS companion decision 正式切到 Laya 命名与协议，并用固定 MIDI 状态证明直接 action choice 的行为边界和实时延迟。

**Non-goals:** 不改变默认 RuleBased 选择，不调整 Aria 生成策略，不训练 Laya。

**Approach:** Swift 端保留一层很薄的 HTTP client，业务 adapter 只负责状态格式化、一个直接 `action` choice question 和结果映射。行为验证复用现有真实 MIDI corpus/state generator，不再维护多套 Prompt profile。

**Acceptance:**
- App 中不存在 Jev/Qwen companion backend 名称或 raw value。
- Laya adapter 直接返回 `listen/support/sparse/yield/respond`，协议错误显式失败。
- 固定 Stage A 可重复运行，记录 action 分布和 p50/p95 latency；不存在全量单类 collapse，关键安全边界满足预设不变量。

**Rules:**
- 通用 HTTP client 不承载钢琴业务规则。
- 只保留一个 action question；不重新引入 semantic decomposition。
- benchmark 样本、seed 和停止条件固定，不通过挑样本改善结果。

---

## P2-T1 将 Swift Jev 接入整体替换为 Laya

**Files:**
- Replace: `HappyPianistAVP/Services/Practice/AI/Networking/JevClassifierClient.swift` -> `LayaClassifierClient.swift`
- Replace: `HappyPianistAVPTests/Networking/JevClassifierClientTests.swift` -> `LayaClassifierClientTests.swift`
- Replace: `HappyPianistAVP/Services/Practice/AI/TurnTaking/JevNetworkCompanionDecisionBackend.swift` -> `LayaNetworkCompanionDecisionBackend.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/TurnTaking/CompanionDecisionBackend.swift`
- Modify: `HappyPianistAVP/ViewModels/Practice/AI/ARGuideAIPerformanceViewModel.swift`
- Modify: `HappyPianistAVP/Views/Practice/Step/PracticeSettingsView.swift`
- Add: `HappyPianistAVPTests/Practice/LayaNetworkCompanionDecisionBackendTests.swift`

**Step 1: transport 命名与协议**

Swift client 改为 Laya 名称，继续 POST `/v1/classifier`，支持 Laya `choice/score/noul` 解码并强制 `output_tokens=0`。`state` 必须支持结构化 JSON object，不能沿用旧 Jev 的预格式化字符串；Laya 对 object 会按自身 `json.dumps` 路径序列化，这样 Swift 产品输入才能与 Python benchmark 使用同一状态结构。测试改用 Laya checkpoint ID 和实际 schema。

**Step 2: companion adapter**

直接发送一个 `action` choice question；criteria 明确定义五种 companion action 的可观察边界。结构化 state 只发送 Laya 决策所需的汇总观测：held/sustain、最近事件间隔、density、pitch center 与 AI playback。执行中测得 120-case 中 76 个包含 16 条 recent notes 的 state 超过 1000 tokens，而去掉逐音符明细后约 170–200 tokens；逐音符明细没有改善 action collapse，反而显著增加延迟，因此从 `AIPerformanceService -> CompanionDecisionInput -> Laya state` 整条链删除 recent notes。删除旧 `formatState` 文本拼接路径。

**Step 3: discovery/settings**

枚举改为 `networkBonjourLaya`，TXT record 改为 `engine=laya-mlx`，UI/错误提示全部改为 Laya。开发期 Jev raw value 不保留兼容分支。

**Step 4: 测试与原子提交**

覆盖 request schema、typed answer、malformed response、未知 action、discovery failure 和无静默 fallback；运行针对性 Swift tests 后提交。

---

## P2-T2 建立统一 Companion 二元语义 benchmark 并重测 Laya

**Files:**
- Reuse: `python_backend/scripts/companion_acceptance_corpus.py`
- Reuse: `python_backend/tests/test_companion_acceptance_corpus.py`
- Add: `python_backend/shared/companion_semantics.py`
- Replace: `python_backend/scripts/companion_laya_benchmark.py` -> `python_backend/scripts/companion_semantic_benchmark.py`
- Replace: `python_backend/tests/test_companion_laya_benchmark.py` -> `python_backend/tests/test_companion_semantic_benchmark.py`

**Step 1: 固定样本**

沿用同一 corpus 索引与 source/state 分层，固定 `seed=20260920`；Stage A 使用 120 cases，并固定 ordered case IDs。状态覆盖 `active_dense / active_sparse / sustain_pause / takeover_overlay / natural_silence / settled_end`，模型都接收相同 compact structured state，不含 `recent_notes`。

**Step 2: 固定模型无关语义协议**

不再直接让任一模型五分类。统一只问四个二元语义：`continuing / finished / space / reasserted`。每个问题使用同一 instructions/criteria，并分别以 `false,true` 与 `true,false` 两种 option order 请求；按语义标签对齐后平均 `true` probability，消除候选顺序偏置。所有后端都使用同一 `semantic_threshold=0.55` 与同一确定性 `semantic-v1` action mapping；`support/sparse` 只由相同 `recent_note_density_per_second=2.0` 阈值区分。

这套 benchmark 必须保持模型无关：未来切到 Qwen 时直接指向另一 classifier server，不能为模型改 state、问题、阈值、mapping、样本或 Gate。

**Step 3: 固定语义与行为 Gate**

关键语义边界必须同时成立：`active_dense continuing=true / finished=false / space=false / reasserted=false`；`active_sparse continuing=true / finished=false / space=true`；`settled_end continuing=false / finished=true`；`sustain_pause continuing=true / finished=false`；`takeover_overlay reasserted=true`。同时要求 `settled_end` 的 respond 高于 `active_dense`，`takeover_overlay` 的 yield 高于 `active_dense`，不得发生全局 action collapse 或跨 MAESTRO/POP909 的方向性冲突。

**Step 4: 延迟与可重复性**

记录 server 与 round-trip latency 的 median/p95/max，以及每个 semantic 的 option-order gap。当前 App 1s request timeout 是硬 Gate，不能通过提高 timeout 获得通过。完整 120-case Stage A 至少复跑两次；ordered case IDs、canonical corpus SHA、semantic scores、actions 必须一致。

**Step 5: Laya 统一协议重测**

旧的 Laya 直接五分类 120/120 `listen` 只保留为诊断证据，不能再作为与 Qwen/CLM 的模型级结论。Laya 必须按上述统一二元语义协议重新评估；若统一协议仍失败，则记录具体 semantic boundary、order gap、cross-source conflict 与 latency blocker，再决定是否进入 P3。

**Step 6: 原子提交**

提交模型无关 semantic protocol、统一 benchmark runner、固定 Gate 与回归测试；输出 evidence 保持 gitignored。

---

## Phase Audit

- Audit file: `audit-p2.md`
- Rule: 完成本 phase 全部 tasks 后，`executing-plans` 必须自动进入该文件的审计闭环
