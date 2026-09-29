# Companion Qwen

## 背景 / 触发

HappyPianist 已确定：`Qwen/Qwen3.5-0.8B` 是当前唯一实验型网络陪伴决策模型，`RuleBasedCompanionDecisionBackend` 保留为默认稳定基线。Laya 等并行实验路径已退出当前产品。

执行前源码审查又确认了几项必须先清理的结构问题：

- Swift 与 Python 各维护一份四语义、A/B 消偏和 action mapping；
- Python E2E 仍构造已经淘汰的 `recent_notes`，随后又在另一个 helper 中静默删除；
- `/v1/classifier` 仍是无人需要的通用多选/动态模型协议，产品实际只需要固定 Qwen companion decision；
- Stage A 的 seed/states/case count/model 仍可从 CLI 改写，且 `--no-gate` 可以绕过 Gate；现有 cross-source conflict 还把 MAESTRO/POP909 两种不同音乐分布的 median 互相当“真值”，会把合法分布差异误判成模型错误；
- 当前 Aria “Streaming”源码先完成整段生成，再切 WebSocket chunk；Swift 也收齐全部 chunk 后才返回，因此它不是实时 streaming，却维护了一整套重复 transport/backend/UI/test；
- 剩余 Aria HTTP 协议还公开 `top_p / strategy / seed`，但 CUDA/MLX server 实际只读取 `max_tokens`；网络解码和 MidiDict 转换还会 clamp、丢弃或凭空补 pitch=60 / velocity=64 / CC64=0，把无效响应修成“合法”输出；
- `AIPerformanceService` 对 Companion 依赖有隐式 RuleBased 默认值，测试漏注入时会悄悄 fallback；`CompanionDecision.confidence` 没有任何消费者；
- Python E2E 的 `realtime_window_pass` 只检查生成 MIDI 的音乐时间，不是墙钟 first-playable latency；同时它重复硬编码了一份产品 generation horizon；
- Stage A benchmark 反向 import E2E script 的共享 helper，文件职责倒置；其 1000ms decision latency hard limit 只来自旧实验提交，而产品控制循环目标周期实际是 100ms。
- `AIPerformanceService` 在 await Companion decision 前拍 state snapshot，但没有把该 decision 绑定 `activationID/phraseGeneration/isAIPlaybackActive`；用户在慢 Qwen 请求期间继续弹奏或播放状态变化时，旧 snapshot 的 decision 可能继续生效。
- 更早的 P14 self-playback guard 仍让“任何用户新输入”直接 `invalidatePendingWindows()` → `cancelAll()`，无条件停止当前 AI playback；这早于现在的 `yield/reasserted` Companion 语义，导致真实产品可能先把 `isAIPlaybackActive` 置 false，再问 Qwen 是否应 yield，绕过了当前决策层。
- control loop 即使已有 generation in-flight 且 AI 当前未播放，仍每 100ms 请求一次 Companion decision；generation completion 又会再做一次 fresh decision。Qwen runtime 用单 `threading.Lock` 串行推理，Swift 超时后 Python `to_thread()` 推理也不会被杀掉，因此慢请求可能形成无效排队并进一步放大 RTT。
- 当前 `space` semantic contract 自相矛盾：Prompt 规定 density `<2.0` 才有 space，但 action mapping 又只有在 `space=true` 后用 density `>=2.0` 产生 `.sparse`；严格遵守 Prompt 时 `.sparse` 不可达。真实 `active_sparse` corpus density 范围是 1–4、两 source 中位数都是 3，因此旧 Stage A 甚至要求模型违背 Prompt 才能过 Gate。
- RuleBased 还把 `isAIPlaybackActive=false` 的快速/密集演奏返回 `.yield`，这是旧 participation mode 机械迁移后的语义债务；当前 `.yield` 应只表示 AI 已在播放且用户重新夺回主导。
- `reasserted` 目前只有 `is_ai_playback_active + 最近用户输入`，无法区分用户音符发生在 AI 开始播放之前还是之后；更糟的是 Queue 在 build/warm-up/真正 `service.play()` 之前就把 `isAIPlaybackActive=true`。因此上一瞬间的用户演奏可能在 AI 刚准备启动时被误判成“重新夺回控制”。

本 feature 先把这些已证实的旧路径和重复职责清掉，再优化 Qwen、重跑服务 E2E，最后才重新实现真正的 Aria 增量生成。

## 核心需求

1. `Qwen/Qwen3.5-0.8B` 固定为唯一实验型网络 Companion 模型；当前目标环境固定 Windows + NVIDIA CUDA，不提供动态 model/device 选择。
2. Qwen service 是网络决策语义的唯一 runtime owner：四个语义、A/B true/false 交换、概率聚合、semantic threshold 与 `semantic-v1` mapping 只在 Python 服务端实现一次。
3. visionOS 只发送 Qwen semantic contract 真正使用的 compact state：`held_notes_count / sustain_value / recent_ioi_median_seconds / recent_note_density_per_second / seconds_since_last_note_on / is_ai_playback_active / user_note_on_since_ai_playback_started`；最后一个字段是产品侧可观察事实，用来区分“AI 开始前已有的用户演奏”和“AI 开始后用户重新进入”。不发送只供 RuleBased/生成 policy 使用的 `recent_velocity_trend / seconds_since_last_user_event / active_pitch_center`。响应使用明确的 `action + semantic scores/order gaps + server_latency/model identity`；Swift 不复制 Prompt、阈值或 mapping。
4. Qwen 网络协议改为专用 Companion Decision API；删除无人使用的通用多选 classifier、动态 candidate labels、动态 request model 和旧兼容 schema。Breaking change 直接升级 Bonjour protocol identity，不做旧协议兼容。
5. Qwen compact state 固定为四语义/mapping 真正使用的 7 个可观察字段；彻底删除 `recent_notes` 生成、剥离和兼容测试，也不把 RuleBased/生成 policy 专用字段继续塞给 Qwen。
6. Stage A 必须先与产品 state projection 对齐，再由版本化 manifest 冻结：Python corpus/benchmark 必须复现 Swift `DuetPhraseBuffer` 的 4s rolling history、2.4s IOI、1.2s density/second、sustain-held note 生命周期与全历史 last-note-on 语义；用同一个跨语言 golden fixture 自动核对。旧 corpus 的 1s density 标签和旧 ordered case IDs 在这一步允许一次性重建，之后才冻结 seed、6 states、每 source/state 10 cases、corpus identity 与新 ordered case IDs；CLI 不再允许改变这些验收变量，也不提供 bypass Gate。
7. Stage A 先修 semantic contract 和 state projection，再冻结 Gate：`space` 表示“是否存在任何陪奏空间（包括 sparse）”；active_sparse/active_dense 的 hard boundary 必须以**产品实际 `recent_note_density_per_second`**筛选，而不是沿用旧 corpus 的 1s raw-count 标签。目标边界仍是 sparse `<=4`、dense `>=8`，4–8 为非硬标签；如果按产品 projection 重建后任一 source 不足 10 个稳定候选，必须调整 state 构造方法并记录依据，不能偷偷放宽模型 Gate。density 2.0 只在 space 已成立后区分 support/sparse。MAESTRO/POP909 分别满足适用 observable boundary；decision RTT P95 hard limit 以当前 100ms control-loop target 为上限。
8. 当前整段生成后分块的 Aria WebSocket 路径全部删除；旧 `network_bonjour_ws_aria_v2` raw value 直接成为无效选择，不做兼容映射。
9. 剩余 Aria network contract 只暴露 server 真正使用的生成参数；未知/越界/缺失 network/model event 必须显式失败，不 silent clamp/drop/补默认 note。无证据的 synthetic `CC64=0` 注入删除；显式配置的 CC7/CC11 policy 保留。
10. 显式选择的 Qwen/Aria/RuleBased/其他生成后端失败时停止该路径并暴露失败，不自动替换后端；生产 service 构造也不得带隐藏 RuleBased 默认依赖。
11. 用户新输入必须立即淘汰未播放的旧 generation / pending window，但不能沿用旧 P14 粗粒度 guard 无条件停止已经开始的 AI playback；是否停止当前 playback 由最新 Companion action 决定。`.yield` 立即停止当前+未来 AI；`.listen` 只停止继续加入并清 future/pending window，不强杀已经开始的短窗口；`support/sparse/respond` 允许当前 playback 继续并生成后续窗口。Queue 的 `isAIPlaybackActive` 必须只表示实际 `service.play()` 已成功开始，不能把 build/warm-up 阶段算作 active playback。
12. 每个异步 Companion decision 必须绑定发起时的 activation/phrase generation/playback phase/post-start-note-on/selection identity，并受 100ms control-loop decision budget 约束；await 期间 identity 失效时，旧 decision 作为正常 stale discard，不记录 backend failure，也不得触发新 generation。Qwen 请求不得在 server/runtime 排队形成 backlog：同一 runtime 只允许一个实际 inference，busy 要 fail fast；产品侧在 playback preparing 或 generation 已 in-flight 且尚未 playing 时不重复发无效 decision，依靠 generation completion 的 fresh decision 做最终提交检查。
13. P2 的 Python runner只证明真实 Qwen + Aria 服务调用与 MIDI 技术合法性，不复制 Swift `DuetPhrasePolicy` 来冒充产品 E2E；产品策略由 Swift 集成测试拥有。
14. P3 只允许真正的增量生成：当前 Aria CUDA sampler 已证实逐 token autoregressive 运行，但必须等一个完整、不可反悔的 MIDI event 边界后才能 emit。普通钢琴 note 至少需要 `note + onset + duration` 三个 token；pedal 需要 pedal + onset。

## 默认值与兼容策略

- Companion 决策未显式选择时仍默认 `ruleBased`；这是用户设置默认值，不是运行失败 fallback。
- 用户显式选择 Qwen 时只接受固定 Qwen Companion service；旧 generic classifier service 不兼容。
- Qwen 新服务使用新的 `path / protocol_version / engine` 组合，避免旧服务被误发现；`engine_impl` 必须精确匹配 `Qwen/Qwen3.5-0.8B`。
- 音乐生成与 Companion 决策仍独立选择。
- 删除假 WebSocket backend 后，已保存的旧 WS raw value返回 invalid selection，由用户重新选择；不自动映射到 HTTP。

## 非目标

- 不恢复或比较其他 Companion 模型。
- P0-P3 不做 Qwen 微调 / LoRA；固定 runtime/prompt 仍无法过 Stage A 时另开训练 feature。
- 不为旧 Qwen classifier、`recent_notes`、假 streaming、旧 WS raw value建立兼容层。
- 不删除仍有独立产品价值的 RuleBased Companion 基线、Local CoreML/Local Rule 音乐生成后端。
- 不把 Aria transport 分块、WebSocket 存在或 MIDI 音乐时间靠前称为实时 streaming。

## 验收标准

- P0：Qwen Companion 语义只有 Python service 一个 runtime owner；Swift/benchmark/E2E 全部调用同一专用 endpoint；旧 generic classifier、`recent_notes` 兼容链、假 Aria streaming、Aria 假参数/silent repair、隐藏 RuleBased initializer fallback 和死 `confidence` API 全部删除；旧“任意用户输入立即停 AI”围栏拆除，由 Companion action 真正控制 playback；慢 decision 的 stale snapshot race 有完整 identity 回归测试。
- P0：固定 Stage A manifest 与 Gate 测试能阻止 corpus/case/threshold 漂移；`space` 与 sparse mapping 不再自相矛盾，五个 action 都有自洽可达测试；MAESTRO/POP909 分别按 observable boundary 验收，source 间 median 差异只作诊断。
- P1：固定 120-case Stage A 重跑两次，可重复且不修改 manifest/contract/Gate；最终全绿或留下明确 deterministic blocker。
- P2：现有 Swift 测试体系只补真实缺口，证明选定 Companion action 会正确进入 policy/generation/queue，且失败不 fallback；真实 Qwen→Aria 服务级 E2E 输出合法 MIDI 并记录真实 wall-clock latency。
- P3：基于 Aria token schema 找到稳定 event commit boundary；只有模型完整生成结束前能输出并播放已确认 event 才实现新的 true-streaming 路径。最终 first-playable wall-clock P95 达到对应产品实时预算，否则以证据停止。
