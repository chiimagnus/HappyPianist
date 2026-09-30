# Plan P0 - 收敛当前架构并删除旧双轨

**Goal:** 在任何新优化前，把 Companion/Qwen/Aria 相关执行路径收敛成单一、严格、可验证的当前架构，删除已证实的旧协议、兼容链、假 streaming 和隐藏 fallback。

**Non-goals:** 不做 Qwen Prompt 质量调参/速度优化，不重跑正式 Stage A，不增加/删除四语义、不改变 `semantic-v1` action 优先级，不实现新的 Aria streaming。允许在 P0 修正已经由源码和 corpus 证明自相矛盾的 semantic criteria/Gate，因为错误合同不能被冻结到 P1。

**Approach:** 先把 Qwen 从“通用 classifier + Swift 重复语义”改成固定 Companion Decision service，使 Python 成为唯一语义 owner；随后冻结 Stage A 的输入与 Gate；删除源码已证明无实时价值的 Aria WebSocket 双轨，并同时收窄 Aria/domain 协议；再清理 Companion 隐式依赖；最后修正旧 P14 playback guard、decision stale identity、timeout 与 runtime 排队。每个 task 自己完成旧路径删除和文档更新，不留“后续再清理”。

**Acceptance:**
- 当前代码中不存在通用 `/v1/classifier` consumer、动态 Qwen model/device、Swift Prompt/semantic mapping、`recent_notes` 兼容链或 `--no-gate`；
- Stage A 的 corpus/cases/state 参数由版本化 manifest + 常量强制，不靠人工约定；
- `space` semantic 与 support/sparse mapping 自洽，五个 action 均有可达性回归；Stage A 按 source 分别验证 observable boundaries，不把 MAESTRO/POP909 median 互相比较当 ground truth；decision RTT P95 Gate 与 100ms control-loop target 对齐，不再保留旧 1000ms；
- 当前整段生成后分块的 WS backend/protocol/client/server route/UI/test 全部删除；
- Aria/domain generation contract 不再包含无消费者 `strategy/sessionID`、optional-seed fallback、重复 seed、假 network params、silent repair 或 synthetic CC64；输入控制器只保留真实被消费的 CC64；
- `AIPerformanceService` 不再有隐式 Companion backend 默认依赖，`CompanionDecision` 不再携带无消费者字段；
- 用户新输入只淘汰 stale pending/future generation，不再绕过 Companion action 无条件停止 active playback；Queue 以单一 `idle/preparing/playing` phase 区分 UI busy 与真实发声；`.yield` 独占“立即停止当前播放”语义，`.listen` 只清 future/pending；
- Companion decision 绑定 activation/phrase/playback/selection identity，总 deadline 与 100ms cadence 一致；generation in-flight + playback inactive 不做无效轮询，Qwen runtime 不允许 inference backlog；
- P0 完成后 build、Qwen targeted Swift tests、Python Qwen/semantic/corpus/Aria protocol tests 与相关 playback/concurrency tests 均通过。

**Rules:**
- Breaking cleanup 直接切断旧协议，不写 alias、migration mapping 或兼容 decoder；
- RuleBased 只作为显式用户默认/显式测试依赖存在，不能作为运行失败兜底；
- 删除假 streaming 时保留 HTTP Aria、Local CoreML、Local Rule 等仍有真实产品用途的生成后端；
- 当前四语义集合、A/B 双顺序、0.55 threshold 与 action 优先级在 P0 不做质量调参；只允许修正 `space` 已证实的逻辑矛盾和由此派生的错误 Gate，再冻结为 P1 真源。

---

## P0-T1 收敛 Qwen 为单一 Companion Decision 服务

**Files:**
- Rename/Modify: `HappyPianistAVP/Services/Practice/AI/Networking/QwenClassifierClient.swift` → `QwenCompanionDecisionClient.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/TurnTaking/QwenNetworkCompanionDecisionBackend.swift`
- Modify: `HappyPianistAVP/ViewModels/Practice/AI/ARGuideAIPerformanceViewModel.swift`
- Rename/Modify: `HappyPianistAVPTests/Networking/QwenClassifierClientTests.swift` → `QwenCompanionDecisionClientTests.swift`
- Modify: `HappyPianistAVPTests/Practice/QwenNetworkCompanionDecisionBackendTests.swift`
- Replace: `python_backend/shared/qwen_protocol.py` with a fixed Companion decision request/response protocol (rename if that makes responsibility clearer)
- Modify: `python_backend/shared/companion_semantics.py`
- Modify: `python_backend/qwen_server/qwen_server/server.py`
- Modify: `python_backend/qwen_server/tests/test_qwen_server.py`
- Modify: `python_backend/scripts/qwen_server.py`
- Modify: `python_backend/scripts/qwen_server_smoketest.py`
- Modify in same task so no broken consumer remains: `python_backend/scripts/companion_semantic_benchmark.py`, `python_backend/scripts/companion_e2e_acceptance.py`, `python_backend/tests/test_companion_semantic_benchmark.py`
- Update: `python_backend/README.md`, `docs/ai-companion-requirements.md`, `docs/architecture.md`, `docs/configuration.md`, `docs/testing.md`

**Current behavior / root cause:**
- Swift 与 Python 都维护四语义 Prompt、A/B 交换、概率聚合和 action mapping；原 P0 再加一份 JSON fixture 只会制造第三层维护。
- `/v1/classifier` 支持任意 choice key、任意 candidate 数、动态 label、动态 request model；全仓真实 consumer 只有当前 Companion 二元 A/B 决策。
- App Bonjour 只筛 `engine=qwen-classifier`，然后信任任意 `engine_impl`；server 也允许 `--model` / `--device cpu`，与固定 Qwen3.5-0.8B + Windows CUDA 的当前决定不一致。

**Step 1: 定义专用 Companion API**

使用 breaking endpoint，例如 `POST /v1/companion-decision`；Bonjour 同步升级到新的 `protocol_version` 与 `engine=qwen-companion`，并要求 `engine_impl=Qwen/Qwen3.5-0.8B` 精确匹配。请求只携带严格 typed Qwen state：`held_notes_count / sustain_value / recent_ioi_median_seconds / recent_note_density_per_second / seconds_since_last_note_on / is_ai_playback_active / user_note_on_since_ai_playback_started`；最后一个字段是产品侧从真实 playback 生命周期与 note-on observation 得到的事实，不是 Swift 预判 `reasserted`。不包含 model、questions、通用 criteria，也不把 RuleBased/生成 policy 专用字段发给模型。

响应携带固定 model identity、最终 `action`、四个 `semantic_scores`、四个 `semantic_order_gaps`、zero-output usage 和明确命名的 `server_latency_ms`。`server_latency_ms` 从已通过 request schema validation 后开始，到 semantic aggregation + action mapping 完成结束；HTTP round-trip 由 caller 单独测，不能继续用含糊 `latency_ms` 混淆 GPU forward 与 server latency。schema 对未知字段 fail closed。Swift 必须同时验证 Bonjour `engine_impl` 与 response model identity 都精确等于 `Qwen/Qwen3.5-0.8B`；TXT、服务实际 model、response 三者任何不一致都显式失败，不能信任“发现到了 qwen-companion 就一定是目标模型”。

**Step 2: Python 成为唯一 semantic runtime owner，并先修自相矛盾的 `space`**

`companion_semantics.py` 唯一保存 4 个 instructions/criteria、`true_on_A/true_on_B`、聚合、threshold、density boundary 与 `semantic-v1` mapping。先把 `space` 明确定义为“用户仍在演奏时，是否存在任何陪奏空间，包括 sparse accompaniment”：
- active + density `<=4` 是明确 positive boundary；
- finished 或 active + density `>=8` 是明确 negative boundary；
- 4–8 的中间带不伪造 Stage A hard truth，可由 IOI/状态作为模型判断上下文；
- density `2.0` 只在 `space=true` 后决定 `.support`（<2）还是 `.sparse`（>=2）；
- `reasserted` 的 necessary condition 是 `is_ai_playback_active == true AND user_note_on_since_ai_playback_started == true`；只有 AI 真正开始播放后的新 note-on 才能进入让位判断，AI 开始前的 recent note/density 不得冒充 re-entry。`takeover_overlay` 固定把该 observable flag 置 true，其它 Stage A state 置 false。

这样 `.sparse` 不再要求模型违反 `space` criteria。增加纯值测试证明 listen/support/sparse/yield/respond 五个 action 都能由自洽的 semantic scores + state 到达。Qwen server 内部构造固定 8-question batch，一次 `_forward_full()` 推理后得到 score/action。benchmark/E2E 只消费服务返回的 scores/action，不再本地重算。

**Step 3: 收窄 Qwen runtime**

删除 generic multi-choice/public question schema、动态 `_labels()`、30-choice 等无真实 consumer 的测试与 warm-up；内部候选只允许固定 A/B。删除 `--model`、`--device` 与 CPU 分支，服务固定加载 `Qwen/Qwen3.5-0.8B` on CUDA，CUDA 不可用直接失败。warm-up 使用与产品相同的 8-question batch 形状，而不是单个 dummy question。

**Step 4: Swift 只负责 state + transport**

`QwenCompanionDecisionClient` 编码 exact state、调用专用 endpoint、严格解码 action/scores/model/usage。`QwenNetworkCompanionDecisionBackend` 只做 discovery、时间差 state projection、client call 与 `CompanionDecision(action:)`；删除 `semanticRules`、Swift A/B question 构造、score aggregation、threshold/mapping 和 missing-semantic-answer 类错误。

同步收窄 domain input：`activePitchCenter` 没有任何 Companion decision consumer，实际只由后续 `DuetPhrasePolicy` 直接从 `DuetPhraseBuffer.Snapshot` 使用，因此从 `CompanionDecisionInput` 删除；不要为了旧 Qwen DTO/测试继续携带。`recentVelocityTrend` 与 `lastUserEventTimestampSeconds` 仍被 RuleBased 使用，保留在 domain input，但不发给 Qwen。

**Step 5: 迁移所有真实 consumer 并删旧入口**

同一 task 更新 semantic benchmark、服务 E2E、smoke 与测试到新 endpoint，然后删除 `/v1/classifier` schema/route/旧类型；不得保留 deprecated wrapper。

**Step 6: 验证**

Run: Qwen server protocol/unit tests + semantic tests

Run: Qwen client/backend targeted `xcodebuild test`

Run: `make build:simulator`

Expected: 新 API 全部通过；Bonjour/service/response model identity 三者严格一致；`CompanionDecisionInput` 不再携带 activePitchCenter；全仓搜索 `/v1/classifier|qwen-classifier|QwenQuestion|ChoiceQuestion` 不存在于当前 Companion 运行路径；产品/benchmark/E2E 都调用同一个专用 service。

**Step 7: 原子提交**

提交专用 Qwen Companion service、所有 consumer 迁移、旧 generic classifier 删除和同步文档。

---

## P0-T2 对齐产品 state projection 并冻结 Stage A 真源

**Files:**
- Add: `python_backend/shared/companion_scenarios.py`
- Add: `Packages/HappyPianistCore/Sources/HappyPianistTestFixtures/Resources/Fixtures/CompanionQwenStateProjection.json`
- Add/Modify: focused Swift projection tests under `HappyPianistAVPTests/Practice/`
- Add: `python_backend/tests/fixtures/companion_stage_a_manifest.json`
- Modify: `python_backend/scripts/companion_acceptance_corpus.py`
- Modify: `python_backend/scripts/companion_semantic_benchmark.py`
- Modify: `python_backend/scripts/companion_e2e_acceptance.py`
- Modify: `python_backend/tests/test_companion_semantic_benchmark.py`
- Modify: `python_backend/tests/test_companion_acceptance_corpus.py`
- Modify: `python_backend/shared/companion_semantics.py` only if obsolete benchmark metadata helpers remain
- Update: `docs/ai-companion-requirements.md`, `docs/testing.md`, `python_backend/README.md`

**Current behavior / root cause:**
- `companion_semantic_benchmark.py` 反向 import 高层 `companion_e2e_acceptance.py` 的 scenario/MIDI/state/helper，职责倒置。
- E2E `decision_payload()` 仍构造 `recent_notes`，`compact_companion_state()` 再静默剥离，属于已废弃输入的完整兼容链。
- Python benchmark state projection 与产品 `DuetPhraseBuffer` 不一致：Python 用 3s context、1.0s raw-count density、物理 note duration；产品用 4s rolling history、2.4s IOI、1.2s count/second density，并把 sustain pedal 下已松键但仍 sounding 的 note 计入 held state。Python last-note-on 还被 context 截断，产品保持最近一次真实 note-on timestamp。
- 执行前抽查当前固定 120 case，用产品 projection 重算后，active_dense/active_sparse 40 case 中有 16 case 不再满足旧 `>=8 / <=4` density hard label；因此旧 corpus identity、旧 ordered case IDs 不能继续被当当前 Stage A 真源。
- Stage A CLI 可以改 `model/seed/cases/states/prompt_window`，`--no-gate` 可以绕过失败；“固定 benchmark”目前主要依赖操作纪律而不是代码。
- `cross_source_direction_conflicts()` 本身口径不成立：MAESTRO 与 POP909 不是 paired samples，而是不同音乐分布；同一粗 state 内 density/IOI 仍可不同。把两个 source 的 median 是否跨阈值当自动失败，会把合法分布差异误判为模型错误。

**Step 1: 建立产品 state projection golden fixture**

复用现有 `HappyPianistTestFixtures` resource bundle，新增一个小型事件时间线 fixture，至少覆盖：普通 note-on/off、sustain-down 后 note-off 仍 sounding、sustain release、密集/稀疏 onset、超过 3s 的 last-note-on。fixture 只描述输入 observation timeline、snapshot time 和期望 Qwen state，不保存 Prompt/模型输出。

Swift 测试通过真实 `DuetPhraseBuffer` + sustain event handling 生成 projection；Python 测试通过新的 `companion_scenarios.py` projection 生成同一 state。两边精确核对 Qwen 真正发送的 7 个字段。不要复制 Swift implementation 细节到 fixture helper，只固定可观察结果。

**Step 2: 收敛共享 scenario/state helper，并严格复现产品算法**

把 `Scenario`、固定 sample、MIDI 读取、`scenario_path` 与 Qwen state projection 移到 `shared/companion_scenarios.py`；benchmark 与 E2E 都依赖它，脚本之间不再互相 import。Python projection 必须复现产品事实：4s rolling history、2.4s IOI、1.2s density/second、sustain-held note 生命周期、全历史 last-note-on；Qwen DTO 不包含 RuleBased/policy 专用字段。HTTP helper不为了两处调用额外抽象。

**Step 3: 彻底删除 `recent_notes` 旧链**

删除 `tail/recent_notes` 生成、`compact_companion_state()` 静默剥离与“removes_recent_notes/all_backends”兼容测试。专用 Qwen request schema 直接拒绝未知 state key，确保旧字段重新出现时显式失败。

**Step 4: 用产品 projection 重建 corpus state 与 Stage A manifest**

修改 corpus candidate 生成/验证：active_sparse/active_dense 的 density hard label必须使用产品 `recent_note_density_per_second`，目标分别 `<=4` / `>=8`；保留原有 next-onset 等可观察条件。重新生成 corpus index 后，先验证 MAESTRO/POP909 每个 required state 都有足够独立文件/候选供 10-case 固定采样；不足时必须回到 state methodology 明确调整，不得在 manifest 层重复/降级 case。

然后生成新的版本化 manifest，固定新 canonical corpus SHA、`seed=20260920`、6 states、每 source/state 10 cases、projection version/参数、ordered 120 case IDs（或同时记录 digest）。runner 每次运行只校验，不自动重建。旧 `40645ac...` / `6abd632...` 仅作为历史证据，不继续当当前 Gate identity。

**Step 5: 删除可改验收口径的 CLI**

移除 `--model`、`--seed`、`--cases-per-state-per-source`、`--states`、`--prompt-window`、`--no-gate`。只保留环境位置（host/port、dataset paths、output）和不会改变 Gate 的运行参数。结果文件在 Gate 失败前照常落盘，因此不需要 bypass flag。

**Step 6: 用 observable boundary 重建 Gate，并固定 latency budget**

删除 `cross_source_direction_conflicts()` 自动 Gate。MAESTRO 与 POP909 的 per-source medians 继续输出作诊断，但不互相充当真值。对每个 source分别检查由重建 corpus construction 保证的 observable boundaries：active_dense continuing=true / finished=false / space=false；active_sparse continuing=true / finished=false / space=true；settled_end continuing=false / finished=true；sustain_pause continuing=true / finished=false；takeover_overlay reasserted=true。某个 source 自己违反边界才失败。

`natural_silence` 不等于“乐句结束”，没有人工 turn-taking ground truth，因此不新增 finished/respond hard truth。4–8 density 中间带也不加入 `space` hard Gate。

把旧 `LATENCY_HARD_LIMIT_MS=1000` 改成由当前产品 `scheduleNextControlTick()` 100ms target 明确拥有的 decision RTT P95 hard limit = 100ms，并写入 Stage A manifest/metadata。以后若产品 cadence 变化，必须作为需求变更同步更新 manifest，不能从 benchmark CLI 临时覆盖。

同步清理 stale `Model-agnostic semantic-v1` 文案，记录实际 Qwen Companion protocol/action mapping identity。

**Step 7: 验证**

Run: Swift/Python state-projection golden parity tests

Run: semantic benchmark/corpus unit tests

Run: manifest dry validation against重新生成后的 corpus index

Expected: Swift/Python Qwen state projection 精确一致；新 fixed case identity PASS；五 action 可达性、per-source observable boundary Gate 与 100ms latency budget metadata PASS；不存在 cross-source median automatic-fail；全仓 `recent_notes` 只允许出现在“禁止重新引入”的长期文档表述，不存在运行代码/兼容测试；runner 无 Gate bypass 与验收口径 CLI。

**Step 8: 原子提交**

提交 projection parity fixture、shared scenario owner、新 corpus/manifest、benchmark 修复、旧兼容链删除与同步文档。

---

## P0-T3 删除伪 Aria Streaming 双轨

**Files:**
- Delete: `HappyPianistAVP/Services/Practice/AI/ImprovBackends/AriaNetworkBonjourWebSocketImprovBackend.swift`
- Delete: `HappyPianistAVP/Services/Practice/AI/ImprovProtocol/ImprovStreamingProtocol.swift`
- Delete: `HappyPianistAVP/Services/Practice/AI/Networking/ImprovStreamingClient.swift`
- Delete: `HappyPianistAVPTests/Networking/ImprovStreamingClientTimeoutTests.swift`
- Delete: `HappyPianistAVPTests/Networking/ImprovStreamingClientValidationTests.swift`
- Modify: `HappyPianistAVPTests/Practice/ImprovScheduleBuilderTests.swift`
- Modify: `HappyPianistAVPTests/Practice/DuetQualityRegressionFixtures.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/ImprovBackends/ImprovBackendKind.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/AIPerformanceService.swift`
- Modify: `HappyPianistAVP/ViewModels/Practice/AI/ARGuideAIPerformanceViewModel.swift`
- Modify: `HappyPianistAVP/Views/Practice/Step/PracticeSettingsView.swift`
- Delete: `python_backend/shared/streaming_protocol_v2.py`
- Delete: `python_backend/scripts/ws_client_smoketest.py`
- Modify: `python_backend/aria_server/aria_server/server.py`
- Modify: `python_backend/aria_server/tests/test_server.py`
- Update: `python_backend/README.md`, `docs/configuration.md`, `docs/architecture.md`, `docs/ai-companion-requirements.md`

**Current behavior / root cause:**
- Python `/stream` 先完整 `await _generate_reply_events()`，之后才 `_chunk_events()`；首 chunk 不可能早于完整模型生成。
- Swift WS backend 又把所有 chunk 收齐成完整 `[ImprovEvent]` 后才返回 `CreativeDuetResponse`；因此当前路径既不降低 first-playable latency，也没有增量 playback，只重复 HTTP 能力。

**Step 1: 删除用户可见 WS backend identity**

从 `ImprovBackendKind`、Picker/status、composition/discovery registry 删除 `.networkBonjourWebSocketAriaV2`；移除独立 WS discovery service。旧 stored raw value不映射到 HTTP，保持现有 invalid-selection 行为。

**Step 2: 删除 Swift WS transport/protocol/tests**

删除 streaming protocol/client/backend 及只验证假 chunk transport 的测试；`ImprovScheduleBuilderTests`/quality fixture 中若仅为 provider 枚举覆盖而重复的 WS case，改用仍存在的 HTTP provider或删除重复 case。

**Step 3: 删除 Python `/stream`**

从 server config/TXT/root route 删除 `stream_window_s`、`ws_path`、`/stream`、`_chunk_events()`、stream start timeout 与 WS handler；删除 shared streaming schema、smoke 和 server streaming tests。HTTP `/generate` 保持功能不变。

**Step 4: 同 task 清理关联死分支**

删除 `AIPerformanceService.failureCategory` 中 WS-specific error 分支。执行前复核确认 `ARGuideAIPerformanceViewModel.setVirtualPerformerEnabled()` 当前只有一次状态赋值，因此不再计划删除不存在的“重复赋值”；不得为了清理指标制造无事实依据的改动。

**Step 5: 验证**

Run: Aria server tests + HTTP smoke

Run: affected Swift networking/backend/settings tests

Run: `make build:simulator`

Expected: HTTP Aria 正常；全仓 `networkBonjourWebSocketAriaV2|AriaNetworkBonjourWebSocket|ImprovStreaming|ws_path|/stream|stream_window` 在 AI 生成路径中为 0；没有 compatibility mapping。

**Step 6: 原子提交**

提交假 streaming 整条链删除和同期文档更新。

---

## P0-T4 收窄生成参数与 Aria HTTP 协议

**Files:**
- Modify/Split: `HappyPianistAVP/Services/Practice/AI/ImprovProtocol/ImprovProtocol.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/ImprovBackends/ImprovBackendProtocol.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/AIPerformanceService.swift`
- Modify/Rename if responsibility improves: current Aria HTTP request/response DTO source
- Modify: `HappyPianistAVP/Models/Practice/CreativeDuetModels.swift`
- Delete: `HappyPianistAVP/Services/Practice/AI/ImprovBackends/ImprovSeedResolver.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/ImprovBackends/LocalRuleImprovBackend.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/ImprovBackends/LocalCoreMLDuetImprovBackend.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/CoreMLDuet/PerformanceRNNImprovGenerator.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/ImprovEngine/Rule/RuleImprovGenerator.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/TurnTaking/DuetPhraseEventBuffer.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/Networking/ImprovBackendClient.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/ImprovBackends/AriaNetworkBonjourHTTPImprovBackend.swift`
- Delete/Rewrite: `HappyPianistAVPTests/Practice/ImprovSeedResolverTests.swift`
- Modify all `ImprovBackendProtocol` test doubles/direct callers under `HappyPianistAVPTests/Practice/` and `HappyPianistAVPTests/Improv/` to remove the deleted generic timeout parameter
- Modify: `HappyPianistAVPTests/Practice/DuetPhraseEventBufferTests.swift`
- Modify: `HappyPianistAVPTests/Improv/RuleImprovAlignmentTests.swift` + its single JSON fixture
- Rename/Modify: `HappyPianistAVPTests/Improv/ImprovProtocolV2CodingTests.swift`, `HappyPianistAVPTests/Networking/ImprovBackendClientV2Tests.swift`, `HappyPianistAVPTests/Practice/ImprovScheduleBuilderV2Tests.swift` as needed to represent the current protocol rather than stale v2 naming
- Replace/Rename: `python_backend/shared/protocol_v2.py` with a current strict Aria network protocol owner
- Rename/Modify: `python_backend/shared/midi_events_v2.py` if `_v2` becomes stale after protocol cleanup
- Modify: `python_backend/aria_server/aria_server/server.py`
- Modify: `python_backend/aria_server/tests/test_server.py`
- Modify: `python_backend/shared/tests/test_protocol_v2.py`, `test_midi_events_v2.py`, `test_cc_policy.py` as applicable
- Modify: `python_backend/scripts/companion_e2e_acceptance.py` or its current name so it uses the current protocol
- Update: `python_backend/README.md`, `docs/overview.md`, `docs/architecture.md`, `docs/configuration.md`, `docs/testing.md`

**Current behavior / root cause:**
- Swift domain `ImprovGenerateParams` 包含 `topP/maxTokens/strategy/seed`，但真实生产读取者只有：CoreML 读取 `topP/maxTokens/seed`，Local Rule 读取 `maxTokens/seed`；`strategy` 没有任何生产读取者。
- `ImprovBackendProtocol` 强制所有 backend 接受统一 `timeout`；Local Rule/CoreML 为此实现 task-group race，但 timeout child 先返回并不能强杀同步/不协作的生成 child，structured task group 退出仍要等剩余 child 收尾，属于名义 timeout。与此同时 `AIPerformanceService.backendTimeout` 默认 12s，而当前 `ImprovQualityRubric.maximumResponseLatencySeconds=0.35` 会把完整 response >=350ms 直接 reject；12s 只会延长无效等待。
- Aria HTTP handler 用 `asyncio.to_thread(pipeline.generate)`，pipeline 再用 blocking `threading.Lock`。Swift request timeout/cancel 不会终止已进入 Python thread/GPU 的旧 generation；随后新请求会在线程里等待旧锁，形成不可见 backlog。
- `CreativeDuetGeneration` 同时保存 `seed` 与 `parameters.seed`；`sessionID` 只用于 `ImprovSeedResolver` 在 seed 缺失时 hash fallback。产品 `AIPerformanceService` 每次都显式生成 seed；Aria server 完全不读取 `session_id`，Local Rule 也忽略它。当前 optional seed → sessionID hash → 0 是无真实产品路径的旧兜底。
- Aria HTTP Python server 实际只读取 `max_tokens`，网络协议却声称 `top_p/strategy/seed/session_id` 都有效。
- Python protocol models 使用 `extra="ignore"`；Swift network decode 会 clamp 越界 note/velocity、负/非有限时间；`ImprovBackendClient` 还用 `try?` 依次猜 result/error，并没有强制校验 `type=="result"` 与当前 protocol version；`mididict_to_events()` 缺 pitch/velocity 时还默认 60/64，并再次 `legalize_events()`。这会把坏模型/网络数据静默修成可播放输出。
- `_generate_reply_events()` 无下游证据却强制补 `CC64=0 @ t=0`。
- 输入侧 `DuetPhraseEventBuffer` 仍记录 CC7/CC11 并暴露无人消费的 `latestValues`；Local Rule/CoreML 只消费 note，Aria prompt 只消费 CC64 pedal。CC7/11 输入数据被记录、传输后静默丢弃。
- 输出侧显式配置的 `DefaultCCPolicy` CC7/CC11 是独立 playback policy，历史上作为明确功能加入，不与上述死输入链或 synthetic CC64 混为一谈。

**Step 1: 删除通用假 timeout，让真实 deadline 由能执行它的边界拥有**

从 `ImprovBackendProtocol.generateCreativeResponse()` 删除通用 `timeout` 参数；删除 Local Rule/CoreML 的 `runWithTimeout()` 与 `.timeout` error case，并同步删除 `AIPerformanceService.failureCategory(for:)` 对这两个假 timeout 的分支。Local 生成的实际耗时仍由 `AIPerformanceService` 观测并进入 quality assessment，不再假装 Swift 能强杀同步生成任务。

Aria HTTP 由 URLSession/network backend 自己拥有真实 deadline；P0 当前非 streaming 路径应从同一个 `ImprovQualityRubric.Thresholds.v2.maximumResponseLatencySeconds` 派生 350ms，而不是保留 `AIPerformanceService` 的独立 12s 常量。Bonjour discovery + HTTP 必须共享这一次 deadline，不能各自重新拿完整超时；`ImprovBackendClient` 也删除自己的默认 2s timeout，必须由 caller 显式传入 remaining deadline。P3 如果建立 true streaming，再把它替换为 first-window deadline + stream lifetime。

**Step 2: 收窄 domain generation metadata**

`ImprovGenerateParams` 只保留 Local Rule/CoreML 真正使用的 `topP/maxTokens/seed`，其中 `seed` 改为必填；删除死 `strategy`。`CreativeDuetGeneration` 删除重复 `seed` 与 `sessionID`，唯一 seed 只存在 `parameters.seed`。删除 `ImprovSeedResolver`、sessionID hash/0 fallback，以及 Local Rule/CoreML 的 `sessionID` 参数。

`RuleImprovAlignmentTests` 的单个旧 JSON fixture 改用 test-local DTO，只保留 `notes/top_p/max_tokens/seed/expected_notes`，删除 `strategy/session_id`，这样 domain `ImprovGenerateParams` / `ImprovDialogueNote` 不再为了历史 fixture 承担文件序列化职责。

**Step 3: 把 Aria network params 与 domain params 分开**

Aria request 只编码 server 真正支持的 `max_tokens`；删除 network `top_p/strategy/seed/session_id` 假控制。若 schema breaking，则升级 Bonjour/network protocol identity，并只保留当前版本；不维护 v2 decoder、typealias 或 migration mapping。

**Step 4: Aria runtime single-flight，禁止取消后的旧推理制造 backlog**

与 Qwen 一样，Aria pipeline 对“正在生成”做非阻塞 admission：已有 generation 在跑时，新 `/generate` 立即返回 machine-readable `busy` + 非 2xx status，不能进入 `threading.Lock` 排队。旧 thread/GPU 因客户端 timeout/cancel 不能被安全强杀时可以自行收尾，但它只占用一个 in-flight slot，不允许积累等待队列。

Swift `GenerationFailureCategory` 增加明确 `busy`（或等价当前命名），network client 按 typed error code分类，不从 message 文本猜。busy 不 fallback 本地 backend、不 client retry；下一次正常 product tick是否再请求由现有 Companion/generation cadence决定。server test 要证明第二个并发 generate fail-fast。

**Step 5: 网络 schema fail closed**

Python request/response models 拒绝 unknown fields、NaN/Infinity、越界 MIDI、负时间和无效 duration；`type` 与 protocol version 都必须是当前 literal。Swift network DTO 同样严格验证并 throw，不能 clamp；client 不再用 `try?` 猜 response kind，而是按 HTTP/status + typed envelope 明确解析。

`ImprovEvent` raw initializer 在全仓没有外部直接构造者；把原始可选字段 initializer 收窄到实现内部，继续以 `.note/.cc` 作为正常构造入口，避免业务代码制造 type 与字段不一致的 event。不要为了这一步重写成新的 enum hierarchy。

**Step 6: 删除 MidiDict / schedule builder 的重复修复**

`mididict_to_events()` 缺 pitch/velocity/start/end、负 duration 或非法 pedal 时显式失败；不要默认 note 60/velocity 64/end=start。`events_to_mididict()` 接收的 domain event 在进入前已经验证，不重复 clamp/drop，只保留必要的 MIDI↔tick 换算。

`ImprovScheduleBuilder` 对当前严格 `ImprovEvent` 不再做 `UInt8(clamping:)` 二次修复；type 对应字段缺失作为不变量失败而不是 `continue` 静默丢事件。Local Rule/CoreML 自己的乐器范围、采样与量化约束继续保留，它们不是网络兼容兜底。

**Step 7: 收窄输入控制器到真实 CC64**

`DuetPhraseEventBuffer` 只记录 sustain CC64；删除 `allowedControllers=[7,11,64]`、`latestValues` 和对应 dead bookkeeping/tests。`DuetPhrasePolicy.buildPromptEvents()` 继续合并 pedal + note。不要影响输出侧 `DefaultCCPolicy` 的 CC7/CC11。

**Step 8: 删除无证据 synthetic CC64**

移除“Always include at least one CC64 for downstream stability”。保留明确配置的 `DefaultCCPolicy` CC7/CC11 注入，并用现有 policy tests证明其独立行为。

**Step 9: 清理当前协议命名**

如果协议已升级，不让 `protocol_v2.py`、`ImprovGenerateRequestV2`、`...V2Tests` 继续伪装成当前真源；同一 task rename/delete旧版本名字，不保留 alias。

**Step 10: 验证**

Run: Aria protocol/midi conversion/server tests + network deadline/single-flight tests

Run: Swift protocol coding/client/HTTP Aria backend + DuetPhraseEventBuffer targeted tests

Run: Local Rule/CoreML seed/determinism targeted tests

Run: HTTP smoke + `make build:simulator`

Expected: 正常请求行为保持；未知/越界/缺失 response 显式失败；不存在 Local fake timeout / AIPerformanceService 12s generation timeout / Aria inference backlog；当前 HTTP Aria 的 discovery+request 使用同一 350ms product deadline，busy fail-fast 且不 fallback/retry；domain 不再有 strategy/sessionID/optional-seed fallback/重复 seed；Aria network payload 只发送真实支持的 max_tokens；Companion/Aria prompt input 只保留 CC64；无 synthetic CC64；全仓旧网络 protocol version 名称不再作为当前 API。

**Step 11: 原子提交**

提交 honest Aria HTTP/domain contract、dead metadata/input controller 与 silent repair 删除，以及同期文档。

---

## P0-T5 删除 Companion 隐式 fallback 与死 API

**Files:**
- Modify: `HappyPianistAVP/Services/Practice/AI/AIPerformanceService.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/TurnTaking/CompanionDecisionBackend.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/TurnTaking/CompanionDecisionBackendRegistry.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/ImprovBackends/ImprovBackendRegistry.swift`
- Modify all test construction sites under: `HappyPianistAVPTests/Practice/` that instantiate `AIPerformanceService`
- Modify if needed: `HappyPianistAVPTests/Practice/RuleBasedCompanionDecisionBackendTests.swift`
- Update: `docs/architecture.md`, `docs/ai-companion-requirements.md` only if wording needs clarification

**Current behavior / root cause:**
- `AIPerformanceService.init` 对 `companionDecisionBackendRegistry` 默认注入 RuleBased，并把 selection 默认成 `.ruleBased`。生产 composition 虽显式传入，但大量测试漏传时会无声走 RuleBased，掩盖依赖遗漏。
- `CompanionDecision.confidence` 在全仓没有业务消费者；当前所有构造都只需要 action。
- `CompanionDecisionBackendRegistry.init(backends: = [])` 与 `ImprovBackendRegistry.init(backends: = [])` 的默认空数组没有生产用途；只有一个测试利用 `ImprovBackendRegistry()` 无参构造 unavailable 场景。默认空 registry 会把漏注入依赖延迟成运行期 unavailable，而不是在构造点暴露。
- `recordPerformanceObservationForPhraseRecordingIfNeeded()` 与 hand-contact 入口在写 note/CC context 前先 `syncBackendDiscoveryIfNeeded()`；因此仅仅因为**音乐生成后端**保存值无效，用户真实演奏就不会进入 Companion state。输入事实不应依赖生成 provider availability。

**Step 1: 强制显式 Companion dependency**

移除 initializer 上两项默认值；生产 composition 保持现有显式注入。所有测试构造点必须明确传入 intended registry/selection：与 Companion 无关的旧 lifecycle 测试明确写 RuleBased；需要验证网络选择的测试显式使用 fake/Qwen，不允许新增 test-only production fallback。

**Step 2: 删除 registry 的隐式空默认值**

`CompanionDecisionBackendRegistry` 与 `ImprovBackendRegistry` initializer 都要求显式 `backends:`；测试需要空 registry 时明确写 `backends: []`。这不是改变 unavailable 行为，只是让“我确实想测试空注册表”变成显式意图。

**Step 3: 删除死 `confidence` 与无用序列化接口**

把 `CompanionDecision` 收敛为仅 `action`；删除未使用属性/default init 参数。P0-T1 已把网络 DTO 与 domain input 分离后，`CompanionDecisionInput` 不再需要 `Codable`；backend kind 的设置持久化只使用 raw string，也不需要为了不存在的 JSON consumer 保留 `Codable`。`CompanionAction` 若 Qwen network DTO 已使用专用 response schema，也同步去掉 domain `Codable`；不为未来可能序列化预留接口。

**Step 4: 把用户输入事实与 generation backend availability 解耦**

从 MIDI/PerformanceObservation/hand-contact 的记录入口删除 `syncBackendDiscoveryIfNeeded()` gate。只要 AI companion 功能启用且 observation role 是 `.userPerformance`，就必须更新 note/CC state、generation identity 与 stale-window state。generation backend selection/discovery 只在 enable/control tick/真正发 generation 前检查；无效或 unavailable provider 仍显式失败，但不能抹掉输入上下文。

增加回归：generation backend raw value 无效时输入仍进入 `DuetPhraseBuffer`；修正选择后的下一次 decision 能看到此前 recent state，同时旧无效选择期间没有 generation 或 fallback。

**Step 5: 核对 invalid/selection-changed 行为**

保留 `invalidSelection / unavailable / selectionChanged` 这三类真实失败，因为它们分别覆盖坏存储值、未注册显式选择、异步请求中用户选择变化；不得把它们合并成 fallback。

**Step 6: 验证**

Run: all Companion backend tests + AIPerformance coordinator/lifecycle targeted suite

Run: `make build:simulator`

Expected: 所有 `AIPerformanceService` call sites 编译时显式声明 Companion dependency；所有 registry 构造都显式给出 backends；输入 state 不再被 generation provider availability gate；不存在隐藏 RuleBased/empty-registry default 或 dead confidence/serialization conformance；现有 selection/no-fallback tests PASS。

**Step 7: 原子提交**

提交显式依赖、空 registry 默认值与 dead API/序列化接口删除。

---

## P0-T6 让 Companion action 真正拥有 playback 让位语义

**Files:**
- Modify: `HappyPianistAVP/Services/Practice/AI/AIPerformanceService.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/Playback/DuetAIPlaybackQueue.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/TurnTaking/CompanionDecisionBackend.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/TurnTaking/RuleBasedCompanionDecisionBackend.swift`
- Modify: `HappyPianistAVPTests/Practice/RuleBasedCompanionDecisionBackendTests.swift`
- Rewrite/rename misleading coverage: `HappyPianistAVPTests/Practice/DuetParallelInputWhilePlaybackTests.swift`
- Modify: `HappyPianistAVPTests/Practice/DuetAIPlaybackQueueTests.swift`
- Add/Modify focused Companion integration tests as needed
- Update: `docs/ai-companion-requirements.md`, `docs/architecture.md`, `docs/data-flow.md`

**Current behavior / root cause:**
- 2026-07 P14 为 self-playback/stale generation 引入：每个用户 observation 都 `invalidatePhraseGeneration()`，随后 `aiPlaybackQueue.invalidatePendingWindows()`；这个 Queue 方法实际走 `cancelAll()`，会停止当前 playback。
- Queue 在 dequeuing window 后、甚至 `buildSequence/warmUp/load/service.play()` 之前就调用 `onPlaybackActiveChanged(true)`；所以当前 `isAIPlaybackActive` 实际混合了“准备播放”和“已经开始发声”两种状态。
- 当前 Companion `reasserted` 明确只在 `is_ai_playback_active=true` 时决定 `.yield`。但真实用户输入可能先把 playback 停掉并把状态置 false，导致 `.yield` 的产品语义被旧 guard 绕过。
- `DuetParallelInputWhilePlaybackTests.aiPlaybackDoesNotBlockSecondContinuousWindowRequest` 只统计 generation call count，没有断言 playback 是否继续，测试名与真实覆盖不一致。
- 长期需求只要求“用户新输入后，未播放的旧 generation 必须失效”；没有要求所有新输入无条件中断已经开始的 AI playback。
- `RuleBasedCompanionDecisionBackend` 仍把 `isAIPlaybackActive=false` 的快速/密集纹理返回 `.yield`；历史显示这是旧 participation `.yield` 在 semantic action 重构时机械迁移留下的语义债务。当前 `.yield` 必须只表示 AI 已在播放且用户重新取得主导。
- 现有 state 也缺少“用户 note-on 是否发生在本轮 AI playback 开始之后”的事实。仅凭 `isAIPlaybackActive + seconds_since_last_note_on/density` 会把 AI 启动前的 recent user input 误判成 reasserted。

**Step 1: 拆开 stale generation 与 active playback**

用户新输入继续立即：递增 `phraseGeneration`、取消 in-flight generation、拒绝旧 generation 的迟到 submit、删除 pending/replacement window、阻止尚未开始 playback 的旧窗口启动。但如果一个 AI window 已经真正 `service.play()` 成功开始，仅因用户输入到达不能自动 stop。

同时纠正 playback 生命周期真源：把当前单 Bool callback 收敛成 Queue 自己拥有的最小 `PlaybackPhase = idle / preparing / playing`。合法 window 被取出、进入 build/warm-up/load 时是 `preparing`；只有 `service.play(fromSeconds:)` 成功后进入 `playing`；失败、结束、stop/cancel 对称回到 `idle`。AIPerformanceService 的外部 `isAIPerformanceActive = isGenerating || phase != .idle`，因此 UI 在 preparing 期间仍保持 busy；Companion state 的 `isAIPlaybackActive = (phase == .playing)`，不再把准备阶段冒充发声。

AIPerformanceService 在每个真实 `.playing` transition 重置 `userNoteOnSinceAIPlaybackStarted=false`；仅用户来源的新 note-on 在 `.playing` 期间把它置 true。note-off、systemPlayback 和 AI 开始前/preparing 阶段的 note-on 不得置 true。不要并行维护 `isPlaybackPreparing + isAIPlaybackActive` 两套独立 Bool。

Queue 需要明确区分“未开始的 stale window”与“已经开始的 active playback”；不能简单抬高一个 generation floor 后让 active playback 在 16ms loop 中自行 return，否则既绕过 Companion action又可能漏 reset。只保留一个清晰的 active/pending 生命周期真源。

**Step 2: 让 action 明确控制停止行为**

给 `CompanionDecision` 建立清晰且不重叠的 playback policy（命名按实现选择，不新增可由 caller 随意组合的 flags）：
- `.yield`：立即停止当前 playback，并清未播放 future/pending windows；
- `.listen`：不请求新 generation，清 future/pending windows，但不强制中断已经开始的当前短窗口；
- `.support / .sparse / .respond`：不因 decision 本身停止当前 playback，可继续生成/排队后续窗口。

`runContinuousControlTick()` 应调用 Queue 的明确 stop-current / clear-pending API，而不是继续用含糊的 `shouldClearFutureWindows + clearPendingWindow` 组合。

同时给 action 建立全 backend 不变量：`.yield` 只能在 `input.isAIPlaybackActive == true && input.userNoteOnSinceAIPlaybackStarted == true` 时返回。RuleBased 对 AI 未播放时的快速/密集纹理改为 `.listen`；已有 RuleBased yield 测试改为真实 active+post-start-note-on，并补 playback=false / active-but-no-post-start-note-on 都不能 yield。不要为了“保持旧测试”保留错误 action。

**Step 3: 保留真正需要的 stale barrier**

generation response、build、warm-up、load 在真正开始 play 前仍必须拒绝过期 `requestGeneration`；disable/session/backend change 仍立即 `stopAll`。不要删除这些已有 correctness guards。

**Step 4: 回归真实 takeover**

至少覆盖：
- Queue phase 顺序为 `idle → preparing → playing → idle`；build/warm-up/load 阶段 UI 仍 busy，但 Companion `isAIPlaybackActive=false`；只有真实 `service.play()` 成功后变 true；
- playback start 重置 post-start-note-on flag；AI active 后用户新 note-on 才把它置 true；
- active playback + 新用户 note-on + pending Companion decision：active playback 在 decision 返回前仍保持 active，旧 pending/future generation 被淘汰；
- decision `.support`：不 stop 当前 playback，并允许当前 phrase generation 请求下一窗口；
- decision `.yield`：立即 stop 当前 playback，发送现有 full reset，不再生成；
- decision `.listen`：清 pending/future，但当前已经开始的短窗口自然结束；
- RuleBased 在 playback=false 的 dense/fast 输入返回 `.listen`；playback=true 但没有 post-start note-on 也不能 `.yield`；
- systemPlayback observation 与 note-off 不得被当成 re-entry note-on。

重写或重命名原 `DuetParallelInputWhilePlaybackTests`，让测试名和断言一致。

**Step 5: 验证**

Run: Companion integration + queue invalidation + parallel-input + self-playback suppression targeted tests

Run: `make build:simulator`

Expected: benchmark 的 takeover_overlay 语义在真实产品生命周期中可到达；所有 backend 的 `.yield` 都满足“真实 playback active + playback start 后新 note-on”前置条件；准备播放不会冒充 active，旧 generation 不泄漏，`.listen` 与 `.yield` 的 current-playback 行为明确不同。

**Step 6: 原子提交**

提交 legacy unconditional-stop guard removal、Queue 生命周期重构与回归测试；不保留旧 `invalidatePendingWindows()` compatibility wrapper。

---

## P0-T7 绑定 Companion decision identity、100ms deadline 与 single-flight

**Files:**
- Modify: `HappyPianistAVP/Services/Practice/AI/AIPerformanceService.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/TurnTaking/CompanionDecisionBackend.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/TurnTaking/QwenNetworkCompanionDecisionBackend.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/Networking/QwenCompanionDecisionClient.swift` after P0-T1 rename
- Modify: `python_backend/qwen_server/qwen_server/server.py`
- Modify: `python_backend/qwen_server/tests/test_qwen_server.py`
- Modify/Add focused tests in the Companion integration test file selected by P0-T6

**Current behavior / root cause:**
- `runContinuousControlTick()` 先拍 note/CC snapshot，再 await decision；当前 helper 返回后只核对 backend selection。
- 用户输入会改变 `phraseGeneration`；P0-T6 后 playback phase 与 `userNoteOnSinceAIPlaybackStarted` 也能独立改变，而 `reasserted` 直接依赖 playing/post-start-note-on。旧 decision 没绑定这些 identity。
- generation 完成后的 second decision 有同类 race。
- control loop 目标周期是 100ms，但 Qwen backend 当前允许 discovery 1s + HTTP 1.5s，单个 tick 的 timeout contract 与产品 cadence 冲突。
- control loop 在 `inFlightGenerateTasks` 非空时仍先请求 Companion decision，之后才因 `shouldRequestWindow()` 拒绝新 generation；若 AI 当前没有播放，这些周期性 decision 没有可执行动作，generation completion 本来就会再做一次 fresh decision。
- Qwen runtime 通过 `threading.Lock` 串行 `classify()`；aiohttp 用 `asyncio.to_thread()` 调它。Swift 请求超时/取消不会终止已经进入 Python thread/GPU 的 inference，后续请求会阻塞等锁，形成 backlog。

**Step 1: 定义单一 decision identity**

每次创建 Companion state 时捕获一个明确 decision identity：`activationID + phraseGeneration + playbackPhase + userNoteOnSinceAIPlaybackStarted + selected Companion kind`。await 返回后必须仍一致；不一致作为 internal stale discard。不要把 wall-clock timestamp 单独当 identity，也不要只比较一个派生 `isAIPlaybackActive` Bool。

**Step 2: 让 100ms 成为一次 decision 的总 deadline**

从 control-loop 100ms cadence 派生一个单一 decision budget；一次 Qwen decision 的 discovery + HTTP + decode 总和不得分别各拿一份 timeout。实现可通过把 remaining deadline 显式传到 backend/client；删除当前 1s/1.5s 独立默认值，避免多层 timeout 互相矛盾。RuleBased 不需要额外 timeout 分支。

Qwen discovery 在启用且当前 selection 为 Qwen 时应尽早启动，但 **decision request 自己不再轮询 Bonjour**。backend 只读一次当前 discovery state：`.resolved` 才发 HTTP；`.idle/.failed` 触发 `start()` 后本 tick 立即返回 unavailable；`.discovering` 直接 fail-fast；`.denied` 显式失败。下一次 100ms tick 再读取异步更新后的 state。删除 `waitForResolvedEndpoint()`、25ms polling 和 `discoveryTimeout`，不把 service discovery 等待算成一次 Qwen inference 的内部重试，也不 fallback RuleBased。

**Step 3: 删除无效 decision 轮询并阻止 runtime backlog**

control loop 不在无可执行动作时浪费 Qwen：
- `playbackPhase == .preparing` 时不发 decision；用户输入若使 preparing window stale，由 Queue generation barrier取消，回到 idle 后再决策；
- generation in-flight 且 phase != playing 时不发 decision，因为不能启动第二个 generation，generation completion 已有 fresh decision 负责最终提交；
- phase == playing 时保留 100ms decision cadence，用于 `.yield/.listen/support/sparse`；
- idle 且无 generation 时正常 decision 决定是否发起下一 window。

Qwen runtime 改成真正 single-flight admission：若一个 inference 已在运行，新的请求立即返回明确 busy/overloaded 错误，不能在线程池里阻塞等 `threading.Lock`。取消/超时的旧 inference 可以自行收尾，但不得让后续请求排成 GPU 队列。对应 server test 要证明第二个并发 request fail-fast，而不是等待第一个完成。

**Step 4: stale/timeout/busy/invalid 分类清楚，并留下最小可观测证据**

identity stale/selection changed 是正常 discard，不调用 failure reporter。真实 backend failure 至少区分：`unavailable`（Bonjour 未解析/拒绝）、`timeout`、`busy`、`invalid_response`（schema/model identity/output-token contract）、`failed`。Qwen server 的 single-flight busy 使用明确 machine-readable error code + 非 2xx status；client 不按 message 文本猜类别。不要为每种底层异常新增 UI 文案，只在现有状态文字保持简洁，并让 `DiagnosticsReporting` 记录 `failure=<category>` 聚合事实。

busy 是当前 selected Qwen 无法在 cadence 内接单的显式 failure，不 fallback RuleBased，也不在 client 侧排队重试。stale 不计 backend failure、不重试、不缓存。当前笼统 `reportCompanionDecisionFailure()` 必须改为接收/映射真实 error category；不得继续把 timeout/busy/schema 全记成 `failure=decision_backend`。

**Step 5: 回归三个 await 窗口与无排队约束**

使用可挂起 fake backend覆盖：
- first control decision pending 期间新 user input；
- decision pending 期间 playback phase 或 post-start-note-on flag 变化；
- generation 完成后的 second decision pending 期间 phrase generation 变化。

另用 fake clock/backend证明超过 100ms 的 decision 被取消/失败且 control loop 不被 1s+ timeout 阻塞；preparing 与 generation-in-flight/non-playing 都不重复调用 decision；Python 并发第二请求在首个 inference 未完成时 fail-fast，不等待锁。

**Step 6: 验证**

Run: focused Companion concurrency/deadline tests + Qwen client/backend tests + Qwen server single-flight tests + existing selection/stale generation tests

Run: `make build:simulator`

Expected: 慢 Qwen 无法让旧 state/旧 playback phase 生效；产品 timeout contract 与 100ms cadence 一致；Qwen decision 内不存在 Bonjour polling；preparing 不冒充 playing，没有无效 decision 轮询或 Python inference backlog；timeout/busy/unavailable/invalid-response 可从低频诊断区分；无 fallback。

**Step 7: 原子提交**

提交 identity-bound decision、fail-fast discovery、单一 deadline、typed failure category 与 single-flight admission；删除旧 1s/1.5s timeout、25ms discovery polling和笼统 `failure=decision_backend`，不留 compatibility overload。

---

## Phase Audit

- Audit file: `audit-p0.md`
- Rule: P0 完成后由 `executing-plans` 自动进入审计；重点扫描旧 generic classifier、recent_notes、fake streaming、Aria fake params/silent repair/synthetic CC64、strategy/sessionID/seed fallback/重复 seed、dead CC7/11 input bookkeeping、hidden RuleBased defaults、dead confidence、legacy unconditional playback stop、stale decision race、1s/1.5s timeout 与 inference backlog、compatibility alias 是否真正为 0；同时确认输出侧显式 CC7/CC11 policy、Local Rule/CoreML 数值域约束等真实业务边界没有被误删。
- Required repo verification: `make doctor` → `make destinations` → `make build:simulator` → `make test:simulator`，并运行全部受影响 Python test suites。全量 Simulator 若仍有既有无关失败，必须逐项与执行前基线对照并记录；不得把 targeted tests 通过写成 full suite 通过，也不得引入新的失败。
- Docs sync: P0 修改了 canonical AI/network/testing 文档，phase close 必须同步 `docs/GENERATION.md` 的源提交、日期与实际验证状态；不要保留 2026-09-26 的旧测试元数据。
