# Module: AVP Practice

AVP practice 由 session state、输入观察与匹配、演奏计划回放、进度、反馈、谱面和 RealityKit overlay 组成。

## 核心对象

| 对象 | 作用 |
| --- | --- |
| `PracticeSessionViewModel` | 对 UI 暴露状态与命令，协调 session effects。 |
| `PracticeSessionStateStore` | 练习 session 的可观察状态真源。 |
| `PracticeRoundConfigurationController` | pending / active configuration。 |
| `PracticeMeasureIndex` | source measure、occurrence 与 step 映射。 |
| `PracticeActiveRange` | 片段的 step/tick/measure 边界。 |
| `PracticeStepNavigator` | 范围内 step 与 measure 导航。 |
| `PracticePlaybackControlService` | autoplay、tempo、回放和输入抑制。 |
| `PracticeProgressCoordinator` | load、checkpoint、flush 和 generation 防护。 |
| `PracticePerformanceAnalyzer` | 一轮内增量 alignment，并在完成边界发布 capability-aware assessment。 |
| `CoachingDecisionService` | 把 assessment 转为一个可复测动作，维护 accept/skip/remeasure 生命周期。 |
| `PracticeLaunchViewModel` | registered request、prepare/apply generation、typed failure、成功 apply 后的 score metadata commit、suspend 与 prepared-song clear。 |

## 曲谱契约

`PracticePreparationService` 的正式输入是 MusicXML。可进入练习的 `PreparedPractice` 必须包含：

- stable song UUID、entry version token 与 score revision
- source/prepared score context 与唯一 `ScorePerformancePlan`
- `PracticeStep[]` 与 `MusicXMLMeasureSpan[]`
- highlight guides 与 `ScoreNotationProjection`

`ScorePerformancePlan` 是 note、tempo、controller、pause、演奏顺序和 provenance 的唯一声音真源。`PracticeStep`、高亮和谱面都是单向投影，不得再保存或生成平行的 tempo、pedal、fermata 或 note-span 声音事实。

不支持“有 steps、无小节”的兼容模式。新增非 MusicXML 来源前，应先定义新的产品模式和数据契约，而不是在现有 session 中添加 fallback。

apply 成功后，launch owner 用 `Set(measureSpans.map(\.sourceMeasureID))` 计算唯一小节总数，并把 resolved entry token、revision、总数与准备时间作为 immutable metadata 异步写入现有 progress repository。当前 generation 先发布 ready，metadata IO 不延长 loading；失败只记录安全 warning。若成功 apply 后 request 已变 stale，旧 generation 不发布 UI，但对应 metadata 仍可幂等落盘。

`HappyPianistAVPTests/Fixtures/PracticeLearningLoopEightMeasures.musicxml` 是测试 fixture，不是产品内置曲目。

## 配置与范围

一轮练习的配置包含 passage、hand mode、tempo scale、loop enabled 和 required successes。曲库不编辑练习配置。

launch owner 在 session apply 前读取该 song 的历史并生成唯一 restore policy：

- exact song UUID + score revision：恢复 active configuration 与位置。
- 只有旧 revision：仅继承 hand mode、tempo scale、loop enabled、required successes。
- 历史损坏：使用 `historyUnavailable`，继续准备当前整首。
- 没有历史：使用 `freshDefaults`。

passage、resume、measure facts、source/occurrence identity 不跨 revision。本轮开始后 active configuration 不可变，练习窗口内的 pending 修改只影响下一轮。

`PracticeActiveRange` 是导航、五线谱 viewport、琴键高亮、autoplay、manual replay 和 round completion 的唯一范围来源。五线谱中心 tick 由 session 即时派生，不持久化。

## 输入观察与匹配

所有输入先投影为 `PerformanceObservation`。它保留 source、capabilities、generation、单调时钟、事件、channel/group、confidence 与 calibration reference；消费者不得从 wall clock 或回放事件反推证据。

| 输入 | 入口 | 当前练习判定 |
| --- | --- | --- |
| 麦克风 | `PracticeAudioRecognitionInputService` | `AudioStepAttemptAccumulator`；只表达目标集合的 detected/contradicted/mixed/unknown。 |
| Bluetooth MIDI | `PracticeMIDIInputService` | `MIDIPracticeStepMatcher`、`ChordAttemptAccumulator`。 |
| 真实/虚拟琴手部 | `PianoKeyContactObservation`、`VirtualPianoInputController` | 每指 started/held/ended observation，再投影为当前 step attempt。 |
| 真实琴手部 gate | `PracticeHandGateController` | `HandPianoActivityGate`。 |

手部接触保留 hand、finger、host 单调时间、置信度、位置、键面距离、法向速度、独立 velocity 与 calibration ID。palm 只可作为活动上下文，不得产生命中。ambiguous/unknown 键位不能被改写成相邻半音的正确音。

matcher 只返回 reducer 需要的 typed outcome。它本身只负责找键和和弦完成；同一份 observation 还会经 session recorder 送入独立的 transient analyzer，形成连续 alignment 与按输入能力裁剪的客观 assessment。该结果不反向改变 step 判定，也不等同专业教学评价。

用户 attempt 必须同时满足：

- session 处于 guiding
- `acceptsPracticeAttempts == true`
- 不是 autoplay、manual replay 或 AI output
- event 属于当前 round generation

## 小节事实与进度

`PracticeAttemptReducer` 把 step attempt 聚合为 source-measure facts：尝试/成功次数、streak、pitch-step stability、本轮最后一次 typed issue 和 resume point。完整 passage assessment 另行归约为可选的 performance maturity 与 metric summaries；两者不互相升级。

规则：

- streak 按手别、tempo 和本轮条件隔离。
- 同一小节发生错误后，后续单个正确 step 不能提前清除该轮错误。
- 已达到 pitch-step stability 的小节不会因未完成的新一轮局部尝试立即降级。
- passage completion 只表示当前练习流程完成；只有 passage assessment 能更新 performance maturity。
- loop 达到 `requiredSuccesses` 后结束，不开始额外一轮。

`PracticeProgressCoordinator` 防止旧曲目或旧 generation 的 load/save 覆盖当前 session。退出、后台、session replacement 和 completion 必须等待 flush。

## 恢复

```text
prepare score
-> load song history and resolve exact / historical / fresh / unavailable policy
-> session applyLaunchRestorePolicy
-> install configuration and active range
-> exact valid 时恢复 step；其余从当前整首 first step 开始
-> remain ready/paused
```

exact revision 的无效 passage/resume 会保留 measure facts，回退当前整首并立即 checkpoint 修复。恢复时不得 note-on、启动 sequencer、预览当前 step 或接受 attempt；用户明确点击继续后才进入 guiding。

## 回放

`PracticePlaybackControlService` 从 `ScorePerformancePlan` 构建片段 timeline。range/seek 起点由 `PerformanceRangeStateResolver` 恢复 controller、held notes 与 pedal-latched notes，`PerformanceTransportReducer` 以 event identity 处理复调同音、重击和 stale note-off。

“示范本节”按 step range 裁出同一条 plan timeline，保留 velocity、tempo、controller、grace、arpeggio 与 fermata。“试听当前音”是独立短 pitch preview，不是 reference playback。

外部 MIDI 使用 look-ahead scheduler 提前发送带 host-time timestamp 的批次；本地 sampler 与外部 MIDI 消费等价的 plan 事件语义。stop、seek、loop、播放错误、音频中断与 route change 都执行同一 reducer reset commands。输出期间输入匹配保持抑制。

发声实现：

- `AVAudioSequencerPracticePlaybackService`：AVP 本地 sampler，需要 `SalC5Light2.sf2`。
- `CoreMIDIPracticePlaybackService`：发送到用户选择的外部 MIDI destination。

## 正反馈

| 派生对象 | 来源 | 展示 |
| --- | --- | --- |
| feedback event | 当前 typed attempt | 顶部非模态 cue、空间恢复效果 |
| musical issue | passage assessment + capability/target evidence | 可解释问题或中性的 evidence check |
| coaching decision | issue + exercise/priority policy | 一个范围明确、可复测的动作 |
| hotspot / next action | 当前 coaching decision；无 assessment 时才用最后一次 typed issue 做基础重试 | 目标小节、速度上限、继续或扩大片段 |
| round summary | active configuration + passage facts + coaching presentation | 动作、范围、手别/指法/声部来源与参考方式 |
| measure map | durable facts | 未开始、练习中、稳定 |

coaching decision、target profile、issue、before/after 关联和反馈 presentation 都不保存到 JSON。进入后台、换曲、restart、窗口关闭和 immersive dismiss 会立即失效；用户可接受动作或从完成摘要显式跳过。

## 录制与 take

- `RecordingTakeRecorder` 保存可重放的 `PerformanceObservation` 和必要的 MIDI 投影。
- `RecordingTakeStore` 保存 `Documents/TakeLibrary/takes.json`。
- `TakePlaybackController` 回放 take。
- `RecordingMIDIExportService` 导出 `.mid`。

麦克风 target detection 不具备可靠逐音 release/velocity，不进入 MIDI take。MIDI take 可由 `RecordedTakeAligner` 对齐到 score event 与 performed occurrence；alignment 和 assessment 保留 unknown、ambiguous 与不可观察维度，仍不能直接当作专业评分结果。

## 启动与退出边界

曲库只登记 request；练习根视图在 active scene 激活它，只有 ready 才挂载 `PracticeStepView`。scene inactive 取消准备并 flush，但保留 request。

显式返回由根视图协调 generation 失效、full leave、progress flush、session recorder 终结、immersive close/recover 与返回曲库；所有可失败持久化完成后才执行无 IO 的 prepared-song 内存提交。意外消失走独立 best-effort close，不触发返回曲库导航；child view 不维护第二套 leave。

## 验证重点

- source/occurrence measure identity 与 repeat
- active range 半开区间、tempo、loop 与 required successes
- wrong/missing/incomplete/unknown typed outcome
- A/B 曲目乱序恢复与 flush-before-teardown
- paused resume 静默与输出 reset
- MIDI timestamp batches、velocity、controller 与 generation guard
- hand contact identity、palm 排除、tracking loss 与 calibration
- bounded alignment、capability-aware assessment 与 target provenance
- coaching evidence gate、单一动作、accept/skip/remeasure 和 lifecycle cleanup

日常功能步骤见 [核心功能测试清单](../testing/core-function-checklist.md)，专业演奏证据见 [钢琴演奏专业化验证手册](../testing/piano-performance-validation.md)。
