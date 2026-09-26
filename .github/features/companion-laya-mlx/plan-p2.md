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

直接发送一个 `action` choice question；criteria 明确定义五种 companion action 的可观察边界。结构化 state 使用与 Python `decision_payload` 一致的字段：held/sustain、最近事件间隔、density、pitch center、AI playback 和 recent notes。修正 `CompanionDecisionInput` initializer，使 recent notes 真正进入运行路径；删除旧 `formatState` 文本拼接路径。

**Step 3: discovery/settings**

枚举改为 `networkBonjourLaya`，TXT record 改为 `engine=laya-mlx`，UI/错误提示全部改为 Laya。开发期 Jev raw value 不保留兼容分支。

**Step 4: 测试与原子提交**

覆盖 request schema、typed answer、malformed response、未知 action、discovery failure 和无静默 fallback；运行针对性 Swift tests 后提交。

---

## P2-T2 建立固定 Laya companion 行为 benchmark

**Files:**
- Reuse: `python_backend/scripts/companion_acceptance_corpus.py`
- Reuse: `python_backend/tests/test_companion_acceptance_corpus.py`
- Add: `python_backend/scripts/companion_laya_benchmark.py`
- Add: `python_backend/tests/test_companion_laya_benchmark.py`

**Step 1: 固定样本**

沿用现有 corpus 索引与 source/state 分层，固定 seed；Stage A 使用 120 case，并固定 case IDs。状态至少覆盖 `active_dense / active_sparse / sustain_pause / takeover_overlay / natural_silence / settled_end`。

**Step 2: 固定行为不变量**

这些不变量只验证 synthetic boundary reproduction，不宣称真人 turn-taking accuracy：`active_dense` 不得大量 `respond`；`takeover_overlay` 应以 `yield/listen` 为主；`settled_end` 与 `active_dense` 必须产生可观察分离；`active_sparse` 不允许单一极端动作吞没全部样本。

**Step 3: 延迟与稳定性**

记录 action 分布、confidence、server latency、端到端 latency 的 p50/p95。以当前 App 1s request timeout 为硬上限；热态 p95 需要留下足够控制环余量。

**Step 4: 最小迭代**

若 Stage A 失败，只允许调整同一个 action question 的 instructions/criteria；不得新增 Prompt profile zoo、额外模型或动态样本。通过后再跑固定 600-case Stage B。

**Step 5: 原子提交**

提交 benchmark runner、固定规则和最小回归测试；输出 evidence 保持 gitignored。

---

## Phase Audit

- Audit file: `audit-p2.md`
- Rule: 完成本 phase 全部 tasks 后，`executing-plans` 必须自动进入该文件的审计闭环
