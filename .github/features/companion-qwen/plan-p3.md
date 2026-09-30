# Plan P3 - 从 Aria token loop 建立真正的 first-playable 路径

**Goal:** 在 Qwen 决策链与服务 E2E 已稳定后，基于 Aria 已有逐 token CUDA sampler，把“完整事件闭合”转成真正早于整段生成结束的可播放 MIDI；做不到则保留单一 HTTP 路径并停止。

**Non-goals:** 不恢复 P0 删除的假 WebSocket backend，不保留 HTTP+streaming 两个并行用户选项，不训练新音乐模型，不把 token/chunk 到达等同于可播放 MIDI。

**Approach:** 当前源码已证明 `sample_cuda.sample_batch()` 使用 KV cache 逐 token 生成；`AbsTokenizer` 对钢琴 note 使用 `instrument/pitch/velocity → onset → duration` 三 token，对 pedal 使用 `PED_ON/OFF → onset` 两 token。因此先在 sampler 层验证“稳定完成事件”的增量解码正确性和真实 latency；只有 emitted event 永远是最终 detokenize 的稳定前缀、且确有足够提前量，才设计新的单一路径 streaming transport 与 product queue 接入。若上游 event boundary/latency 不成立，P3 直接 Blocked，不在网络层继续切块。

**Acceptance:**
- 能独立测量 model first token、first complete MIDI event、generation complete、network first event 与 product first playback 的 wall-clock latency；
- 所有增量 emit event 与最终完整 detokenize 输出逐项一致，时间顺序不倒退；
- 若实现 true streaming，产品在完整 generation 结束前已将至少一个稳定 event 交给 playback queue；用户新输入/disable/backend change 能取消未播放 future events 且无挂音/踏板；
- 最终 fixed-case 结果按 action 分层报告。Qwen decision RTT 继续记录但不作为 P3 Gate。现有 `ImprovQualityRubric.maximumResponseLatencySeconds=0.35` 当前约束的是**完整 generation response latency**，不是 first-playable；P3 只有在把质量评估改成“首个可独立验收 playable window”后，才能把同一个 350ms 用户等待上限迁移为 Aria request→first accepted playable window 的 Gate。full completion latency 单独报告，不再混入这个维度；
- 若 streaming 不值得/不正确，只保留 P0 的 HTTP 单一路径，并记录上游 blocker。

**Rules:**
- 只有完整稳定 MIDI event 才能跨网络，不发送半个 note token group；
- malformed token sequence、onset 倒退或无法确定 duration 的事件必须留在 server buffer，不能猜；
- 真 streaming 一旦替代 HTTP network Aria，旧 HTTP product path/API/枚举/测试必须在同一 task 删除，不保留 fallback；Local CoreML/Local Rule 不受影响；
- 主 Actor 不做 token decode/network parsing 重活；
- 诊断只记录 timing/count/错误类别，不记录原始 MIDI、Prompt 或模型正文。

---

## P3-T1 验证 Aria stable-event commit boundary 与提前量

**Files:**
- Inspect/Modify experiment hook if needed: `python_backend/aria/aria/inference/sample_cuda.py`
- Reuse: installed/pinned `ariautils.tokenizer.absolute.AbsTokenizer` behavior
- Add focused pure decoder/prototype tests under: `python_backend/aria_server/tests/` or `python_backend/tests/`
- Reuse fixed generating cases from: P2 service E2E evidence
- Evidence: ignored `.outputs` only

**Current source facts:**
- `sample_batch()` 已在 Python for-loop 中逐 token 采样并维护 KV cache，只在循环结束后统一 `tokenizer.decode()`/return。
- AbsTokenizer 普通 note 的稳定最小单元是三 token：note identity/velocity、onset、duration；pedal 是 pedal token + onset；`<T>` 改变后续 5s time segment offset。

**Step 1: 写最小 stable-prefix decoder/prototype**

不要先建网络协议。对 sampler 已生成 token prefix 维护 time-segment 与 pending event state；只有合法 note 三元组或 pedal 二元组闭合时才产出 event。special/dim/eos/malformed 序列必须有明确处理；不得通过反复 detokenize 整个 prefix 来隐藏状态错误，除非只用于测试 oracle。

**Step 2: 用最终 detokenize 作为 oracle**

对 synthetic token sequences 和真实 Aria generation：每次 incremental emit 后，最终完整 sequence detokenize 得到的事件必须包含完全相同的已 emit prefix（pitch/velocity/onset/duration/pedal 均一致）；任何 later token 能改变旧 event 就判 No-Go。

**Step 3: 验证时间单调性**

如果模型生成一个比已 emit event 更早的 absolute onset，不能在客户端重新排序已经播放的事件。测真实 case 是否出现；若出现，定义能够等待到安全 boundary 的最小 buffer，仍无法保证则 streaming No-Go。

**Step 4: 真实 Windows CUDA latency probe**

在 P2 generating case 子集记录：generation start、first token、first stable event、full completion。比较 first-stable-event 与 full generation 分布；同时结合 P1 decision RTT 计算从 decision request 到 first stable event 的技术下界。

**Step 5: Gate**

只有同时满足：
- incremental event prefix 100% 与 final output 一致；
- onset/order 可安全提交；
- first stable event 明显早于 full completion，并且存在把若干 stable events 聚成首个**可独立通过产品质量检查**的 playable window、在 350ms 内完成的现实可能；单个 stable token/event 提前但必须等完整 generation 才能过 quality gate，仍视为 No-Go；

才进入 P3-T2。否则 P3 标 Blocked，不提交 transport/product streaming 代码。

**Commit:** 纯实验无长期代码时不提交；若 stable decoder 是后续实现必需且已有纯值测试，可原子提交它与测试。

---

## P3-T2 用单一路径实现 true streaming，或保持 HTTP 并停止

**Files:**
- Modify only if P3-T1 Pass: `python_backend/aria/aria/inference/sample_cuda.py`
- Modify: `python_backend/aria_server/aria_server/server.py`
- Add/Modify one streaming protocol/transport only if required by proven design
- Modify: current Aria network backend under `HappyPianistAVP/Services/Practice/AI/ImprovBackends/`
- Modify: `HappyPianistAVP/Services/Practice/AI/AIPerformanceService.swift`
- Modify: `HappyPianistAVP/Services/Practice/AI/Playback/DuetAIPlaybackQueue.swift` only for actual incremental scheduling needs
- Add focused server/network/playback tests
- Update same task: `python_backend/README.md`, `docs/architecture.md`, `docs/data-flow.md`, `docs/configuration.md`, `docs/ai-companion-requirements.md`

**Step 1: 根据 P3-T1 选择最小 transport/API，并固定 CUDA capability identity**

只在 stable event 可增量产出时设计 transport。可以使用真正逐 event/window 的 WebSocket/streaming HTTP，但 transport 名称不重要；关键是 server 在 full generation 完成前发送 stable event。不得复制 P0 删除的“先 full generate 再 chunk”实现。

当前 Aria Bonjour 已广播 `engine_impl=aria-cuda / aria-mlx`。如果 P3 只在 CUDA sampler 实现 true streaming，新 product discovery 必须把 `engine_impl=aria-cuda` 设为 required TXT，同时升级 path/protocol identity；不能只要求 `engine=aria` 后把 MLX server 当成同能力实现。MLX 可以保留其独立 CLI/offline用途，但不能被当前 true-streaming product backend 误发现。

**Step 2: 保持一个用户可选 Aria 网络后端**

如果 true streaming 成为产品网络 Aria 路径，就让一个新的当前协议/backend identity 替代旧 HTTP network backend；同一 task 删除被替代的 HTTP product enum/client route/discovery/test，不做 fallback/alias。Server 若仍需非产品 HTTP endpoint 作为离线诊断，必须证明它有独立用途；否则一起删除。

**Step 3: 产品逐增量调度**

AIPerformanceService/queue 只能调度已经 stable 的 events。generation/phrase/backend identity 必须随 stream 保存；用户新输入、disable、session/backend change 立即取消 server stream 和未播放 future events。已开始的 note/pedal teardown 继续使用现有 queue/transport reset 不变量，不创造第二套 cleanup。

**Step 4: 把质量检查收敛到可独立提交的 mini-window，而不是单 event**

不能把 stable event 直接播放后再补做当前完整-response quality gate。先定义最小 playable window：包含完整 note lifecycle、能够经过 `DuetPhrasePolicy.shapeSchedule()/assessSchedule()`，且不会因为未来 token 到来修改已提交事件。

把质量维度按“可在 prefix/window 上安全判断”与“需要完整 window 终点”拆清楚：MIDI 合法性、内部 note conflict、register、与用户 held/pitch-center conflict、局部 density/rhythm/voice-leading 可以在 committed window 上判断；`ImprovQualityRubric` 的 cadence/motivic repetition 等依赖完整 window 终点或更长上下文的维度，不能拿任意 token prefix硬判。实现应让这些维度在真正的 window boundary 再判断，而不是关闭它们。

现有 `responseLatencySeconds` 当前表示 full backend response latency。若 true streaming 生效，将这个维度**明确重命名**为 first-playable/first-window latency，并以“首个通过所有当前可适用 quality checks 的 window 被接受”为时间终点；full generation completion latency 另做 diagnostics。不要让同名字段悄悄换语义。

**Step 5: 验证**

Run: Aria server incremental tests（必须证明 first message occurs before model completion）

Run: Swift transport/parser tests（顺序、取消、malformed、timeout）

Run: AIPerformance + playback queue cancellation/stale/no-stuck-note targeted tests

Run: `make build:simulator`

Expected: full generation 未结束时已发生首个合法 schedule submit；取消/代际切换无旧事件泄漏；不存在并行 HTTP fallback backend。

**Step 6: 原子提交**

提交唯一 true-streaming 路径和同 task 旧路径删除；探索 transport 不保留。

---

## P3-T3 用固定 case 验收真实 first-playable wall-clock latency

**Files:**
- Modify service E2E runner to consume true-streaming API if P3-T2 exists
- Reuse: fixed P2 60-case IDs / Stage A manifest
- Modify targeted Swift diagnostics/tests if needed
- Evidence: ignored `.outputs` + AVP 真机聚合 timing evidence
- Update: `docs/testing.md`, `docs/ai-companion-requirements.md`

**Step 1: 定义不歧义的时间点**

分别记录：Qwen request start/action ready、Aria generation request start、server first stable event、network first accepted mini-window、first schedule submit、`PracticeSequencerPlaybackService.play()` 成功进入 playback、full generation complete。不得再用 MIDI event 的 `time` 字段冒充 wall-clock latency，也不得把“收到一个 token/event”算作 playable。`play()` 成功是 App 内部 first-playback boundary，不声称等于外部钢琴/扬声器的物理声学 onset。

**Step 2: 固定 service case 对照 P2**

Windows service runner 使用与 P2 相同 generating cases；比较 full generation time、first stable/window time、技术失败率和输出合法性。Qwen decision 必须仍由 P1 固定 service/Stage contract 产生。该 runner只证明 server/协议提前量，不记录不存在的 AVP playback start。

**Step 3: AVP 真机测 app-level first-playable**

在 Apple Vision Pro 上连接同一 Windows CUDA Aria/Qwen service，使用当前产品 routing 跑真实 Companion 生成。只记录聚合时间点/count，不记录 MIDI/Prompt/host。至少能把 Aria request start → first accepted mini-window → first schedule submit → playback service `play()` success 串成同一 generation identity；取消/stale generation 样本不能混入成功 latency 分布。

若没有可用 Vision Pro/局域网环境，真机部分标 `blocked evidence`，不能用 Windows localhost 或 Simulator 冒充产品 first-playable。

**Step 4: Action-aware realtime Gate**

按生成 action 分层报告 latency，但不要把 `DuetPhrasePolicy.requestWindowSeconds` 当响应预算；它是生成音乐的 horizon。Qwen decision RTT 只记录，不再作为 P3 Gate。Aria 只有在 P3-T2 已把 quality latency 语义迁移到 first accepted playable window 后，才使用 `<350ms` Gate；服务级 Gate 的时间终点是**通过 applicable quality checks 后形成的首个 accepted mini-window**，产品真机证据还要单独报告该 window 到 schedule submit / playback `play()` success 的开销。不是 first token、first stable event、network first byte 或 MIDI 的 `time` 字段。full generation completion latency 与 decision request→actual playback start 总时延都单独报告，不发明额外 hard limit。

**Step 5: 正确性回归**

MIDI 技术合法性、quality guardrail、generation success、取消/stale selection/disable teardown、无挂音/踏板都不得比 P2/现有产品测试退化。true streaming 必须在 Swift 源码与测试中把旧 full-response latency 维度显式重命名/重定义为 first accepted playable-window latency；原 full response completion latency 只做 diagnostics。cadence/motif 等完整-window 维度不能因为 streaming 被静默跳过。

**Step 6: 结论**

只有 service fixed-case Gate + AVP app-level first-playable evidence都通过，才宣称当前 Aria 路线实现产品内实时 first-playable；缺真机则结论保持 blocked evidence。若失败，记录具体 bottleneck（model first-event、mini-window quality boundary、transport、policy buffer、playback）并停止继续叠 transport workaround。外部 MIDI/扬声器物理 onset latency若没有同步测量，继续明确为未证明，不把 `play()` success 改写成声学延迟。

**Commit:** 只有 runner/diagnostics 的长期修复需要提交；实验结果本身进入 audit/todo evidence。

---

## Phase Audit

- Audit file: `audit-p3.md`
- Rule: 审计必须从时间戳证明首个 accepted playable mini-window 发生在 full generation 完成前；检查没有重新引入双 Aria network backend、假 chunking、扩大 window、跳过 cadence/motif quality checks 或取消/teardown 回归。
- Required repo verification: 若 P3-T2 实现 true streaming，必须跑 `make doctor` → `make destinations` → `make build:simulator` → `make test:simulator`，并跑完整 Aria server/incremental protocol tests、fixed service cases 和真机 first-playable evidence。若 P3-T1 No-Go 且没有 Swift 实现变更，只运行实验/服务测试并明确停止，不制造无意义 build claim。
- Docs sync: 最终更新 canonical architecture/data-flow/config/testing/AI 文档后刷新 `docs/GENERATION.md`；只有实际真机证据通过才写“产品实时 first-playable 已验证”。
