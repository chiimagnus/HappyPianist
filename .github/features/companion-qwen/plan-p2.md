# Plan P2 - 当前 Qwen + Aria 服务链与产品 glue 验证

**Goal:** 在固定 Qwen Companion 合同下，证明当前 Companion action 能正确驱动产品 policy/lifecycle，并验证真实 Qwen→Aria 服务调用与 MIDI 技术合法性；P1 语义缺口不阻止服务链技术验证。

**Non-goals:** Python runner 不复制完整 Swift `DuetPhrasePolicy`，不声称替代 visionOS 产品 E2E；不优化 Aria 生成速度，不实现 streaming；P1 blocked 时不得把 P2 技术链路成功写成产品决策通过。

**Approach:** 产品 policy 真相留在 Swift：复用已有大量 coordinator/queue/policy/lifecycle tests，只补 `AIPerformanceService` 目前缺失的 Companion backend glue。Python runner则明确降级为“服务级 E2E”：固定从 Stage A manifest 取 60-case 子集，真实调用 Qwen Companion service 与 Aria HTTP，验证网络、schema、MIDI 合法性和 wall-clock latency；删除伪 realtime-window 指标和重复 product horizon。

**Acceptance:**
- Swift 自动化明确覆盖选定 Companion backend → decision → generation/no-generation/selection-change/error 的 service glue，且不复制已有 queue/policy lifecycle tests；
- Python 服务级 E2E 不再本地重算 semantics/action，不再重复 `DuetPhrasePolicy` window；
- 真实 Qwen 与 Aria 服务请求成功，所有成功生成 MIDI 可重新解析、Note On/Off 合法、无明显 prompt echo；
- 记录 Qwen RTT、Aria HTTP RTT/server latency、action/source/state 分布与失败 case IDs；
- Apple Vision Pro 真机在同一局域网下单独记录 Qwen decision RTT p50/p95/p99、timeout/busy/invalid 次数；没有真机证据时状态明确为 blocked/pending，不能用 Windows localhost 代替；
- 结果明确标注“service E2E ≠ product realtime pass”。

**Rules:**
- P1 语义 Gate 未 Pass 时，P2 仍可完成服务链技术验收，但不得把 P2 成功写成 Qwen 语义质量或 visionOS 产品实时性通过；
- 不重新引入 fake streaming/WS backend；
- 生成样本和结果保持 ignored；
- 不新增新的 production abstraction 只为测试。

---

## P2-T1 只补 AIPerformanceService 的 Companion glue 缺口

**Files:**
- Reuse/Modify: `HappyPianistAVPTests/Practice/AIPerformanceCoordinatorTests.swift`，或若继续塞入会进一步破坏职责，则新增一个专门的 `AIPerformanceCompanionIntegrationTests.swift`
- Modify production only if test exposes real bug: `HappyPianistAVP/Services/Practice/AI/AIPerformanceService.swift`
- Reuse unchanged after P0: `DuetPhrasePolicyTests.swift`, `DuetAIPlaybackQueueTests.swift`, `DuetDisableTeardownTests.swift`, `DuetOutOfOrderResponseTests.swift` and the P0-T6 Companion/playback integration coverage that replaces or renames the misleading old `DuetParallelInputWhilePlaybackTests.swift`

**Current coverage / gap:**
- 已有测试分别覆盖 action→RequestPolicy、schedule shaping/quality、queue replace/clear/teardown、stale generation、backend generation error；不要重写这些。
- 当前 `AIPerformanceService` 测试此前依靠默认 RuleBased，且没有显式 fake Companion backend，因此 `requestCompanionDecision()` 到 generation control 的 glue 没被直接锁定。

**Step 1: 增加最小 fake Companion backend**

只支持返回指定 `CompanionDecision`、抛指定错误、必要时挂起一次决定以模拟 selection change；不要增加生产 factory/fallback。

**Step 2: 只覆盖缺失 glue**

至少证明：
- 显式 `.listen` 不调用 generation backend；
- 显式 generating action（选一个 `.support` 即可；其它 action→policy 已由 `DuetPhrasePolicyTests` 覆盖）会进入 generation；
- Companion backend error 时本 tick 停止，generation backend 不被调用，也不改用 RuleBased；
- 请求挂起期间 selection 改变会丢弃旧 decision，不启动 generation。

不要在这里重复 queue stopAll、多个 action window 数字、quality rubric 等已有测试。

**Step 3: 验证**

Run: new/modified Companion integration tests + existing Qwen backend tests

Run: existing Duet lifecycle targeted suite

Run: `make build:simulator`

Expected: 新 glue tests PASS；已有 policy/queue/lifecycle tests 不退化。

**Step 4: 原子提交**

测试本身可提交；只有暴露真实生产 bug 时才同步提交最小根因修复。

---

## P2-T2 重构并运行真实 Qwen → Aria 服务级 E2E

**Files:**
- Rename if clarity improves: `python_backend/scripts/companion_e2e_acceptance.py` → `companion_service_e2e.py`
- Reuse: `python_backend/shared/companion_scenarios.py`
- Reuse: current Qwen Companion API
- Reuse: the current strict Aria HTTP protocol owner produced by P0-T4; do not refer back to deleted `protocol_v2.py`/v2 aliases
- Add/Modify focused runner tests if needed under: `python_backend/tests/`
- Evidence: `python_backend/.outputs/companion-qwen-e2e/`
- Update: `python_backend/README.md`, `docs/testing.md`, `docs/ai-companion-requirements.md`

**Current behavior / root cause:**
- runner 的 `generation_horizon_seconds()` 手写复制 Swift window，却没有复制 action-specific maxTokens；它不是产品 policy 真源。
- `realtime_window_pass` 只检查“生成 MIDI 的 note time 是否落在 0.45/0.6/0.7s 内”，没有测真实 wall-clock first playable，因此命名误导。
- runner 仍有 `--decision-only/--qwen-model/--seed/--states/--cases...` 等历史通用入口；P0 后已有单独固定 Stage A，不需要这些双轨。

**Step 1: 明确 service-E2E 职责**

runner 固定使用 P0 Stage A manifest 的 60-case 子集（每 source/state 前 5 个 ordered IDs），真实 POST Qwen Companion endpoint；直接消费 server action/scores。删除 decision-only 与动态 model/case/state/seed 选择。

**Step 2: 删除伪产品 policy / realtime 指标**

删除 `generation_horizon_seconds()`、`realtime_window_pass*`。Aria 使用一个明确固定的技术验证 token budget；不要声称等价于 `DuetPhrasePolicy`。产品 action→window/token 真相只由 Swift tests 验证。

**Step 3: 记录真实 wall-clock 技术指标**

对每 case 记录 Qwen HTTP RTT/server latency、Aria HTTP RTT/server latency、action、generation attempted/succeeded/error。`first_note_time` 只作为生成 MIDI 内容属性，不命名为 latency/realtime。

**Step 4: 技术合法性 Gate**

所有实际生成响应必须通过 schema/MIDI reparse、合法 note/velocity/timing、Note On/Off 配平与 prompt-echo 检查；技术错误按 case 记录并使最终 runner 非零退出。必须至少有真实 generating action 与成功 Aria generation，否则整轮失败。

**Step 5: 完整运行 x2**

Windows 同时启动固定 Qwen CUDA service 与 Aria CUDA HTTP service；两次使用同 60 case IDs。Qwen action 应与同 manifest Stage A 对应 case 一致；Aria sampling 可以变化，但技术 Gate 必须稳定。

**Step 6: 原子提交**

提交 runner 职责收敛/测试/文档；生成 MIDI/结果 JSON不提交。

---

## P2-T3 真机验证 Vision Pro → Windows Qwen decision RTT

**Files:**
- Modify only if missing: low-frequency aggregate timing diagnostics in `HappyPianistAVP/Services/Practice/AI/Networking/QwenCompanionDecisionClient.swift` / `AIPerformanceService.swift`
- Modify targeted diagnostics tests if instrumentation changes
- Update evidence only: `docs/testing.md`, `todo.toml` note / audit evidence

**Goal:** 补上 P1 localhost Stage A 无法证明的产品网络层，不把 Simulator 或 Windows 本机 RTT 冒充真实 Vision Pro 局域网性能。

**Step 1: 只记录聚合 timing**

在不记录 state/MIDI/Prompt/地址的前提下，区分一次成功 Qwen decision 的 client request start → HTTP response/decode/action ready；记录 p50/p95/p99 与 sample count。timeout、busy、invalid-response 只记类别计数。不要把 Bonjour host、原始 payload 或模型正文写进可导出日志。

**Step 2: 固定环境真机 smoke**

在 Windows RTX 4060 启动 P1 已通过的固定 Qwen service；Apple Vision Pro 与 Windows 在同一局域网。显式选择 Qwen，运行足够多真实 control ticks，并记录 commit、visionOS、Windows/GPU、网络环境、sample count。

**Step 3: Gate 与证据边界**

产品 control-loop 仍以 100ms 为目标，因此成功 decision RTT P95 应 `<100ms`；timeout/busy 不得靠 RuleBased fallback 掩盖。若无可用真机或网络环境，不伪造结果，P2-T3 标 `blocked evidence`；P2-T1/T2 的代码/服务验证仍可完成，但不能宣称“产品 decision latency 已通过”。

**Step 4: 原子提交**

只有 instrumentation/test/文档发生代码变更时提交；纯真机证据不为了留下 commit 制造代码差异。

---

## Phase Audit

- Audit file: `audit-p2.md`
- Rule: 审计必须区分 Swift 产品 glue 与 Python 服务 E2E；禁止把 Python runner 的音乐时间、HTTP 成功或旧历史结果写成 visionOS realtime/product 验收。
- Required repo verification: `make doctor` → `make destinations` → `make build:simulator` → `make test:simulator`，再运行 P2 service-E2E runner/tests。真机 RTT 属于额外产品证据，不替代 Simulator build/test；无真机时明确 `blocked evidence`。
- Docs sync: 更新 `docs/testing.md` / AI 文档后同步 `docs/GENERATION.md`，只写实际完成的 Simulator/Windows/AVP 证据。
