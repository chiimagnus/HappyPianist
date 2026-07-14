# Module: AVP Practice

AVP practice 由 session state、输入匹配、回放、进度、反馈、谱面与 RealityKit overlay 组成。

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
| `PracticeLaunchViewModel` | registered request、prepare/apply generation、typed failure、成功 apply 后的 best-effort score metadata commit、suspend 与 prepared-song clear。 |

## 曲谱契约

`PracticePreparationService` 的正式输入是 MusicXML。可进入练习的 `PreparedPractice` 必须包含：

- stable song UUID 与 score revision
- `PracticeStep[]`
- `MusicXMLMeasureSpan[]`
- tempo、pedal、fermata 等时间线
- highlight guides
- notation 输入

不支持“有 steps、无小节”的兼容模式。新增非 MusicXML 来源前，应先定义新的产品模式和数据契约，而不是在现有 session 中添加 fallback。

apply 成功后，launch owner 用 `Set(measureSpans.map(\.sourceMeasureID))` 计算唯一小节总数，并把 resolved entry token、revision、总数与准备时间作为 immutable metadata 异步写入现有 progress repository。当前 generation 先发布 ready，metadata IO 不延长 loading；失败只记录安全 warning。若成功 apply 后 request 已变 stale，旧 generation 不发布 UI，但对应 metadata 仍可幂等落盘。

`HappyPianistAVPTests/Fixtures/PracticeLearningLoopEightMeasures.musicxml` 是测试 fixture，不是产品内置曲目。

## 配置与范围

一轮练习的配置包含：

- passage
- hand mode
- tempo scale
- loop enabled
- required successes

曲库不编辑练习配置。launch owner 在 session apply 前读取该 song 的历史并生成唯一 restore policy：exact song UUID + score revision 存在时恢复其 active configuration 与位置；exact 不存在时，deterministic resolver 只选择最近 identity 的 hand mode、tempo scale、loop enabled、required successes。passage、resume、measure facts、source/occurrence identity 与 score revision 不进入历史偏好模型，因此不会跨 revision。历史损坏使用 `historyUnavailable`，没有可用配置使用 `freshDefaults`；两者都继续准备曲谱。本轮开始后 active configuration 不可变，练习窗口内的 pending 修改只影响下一轮。

`PracticeActiveRange` 是以下消费者的唯一范围来源：

- 导航
- 五线谱 viewport
- 琴键高亮
- autoplay
- manual replay
- round completion

换曲或 score revision 改变时必须安装新曲目的范围，不能复用上一首曲目的 passage。

## 输入与匹配

| 输入 | 服务 | 主要判定对象 |
| --- | --- | --- |
| 麦克风 | `PracticeAudioRecognitionInputService` | `AudioStepAttemptAccumulator` |
| Bluetooth MIDI | `PracticeMIDIInputService` | `MIDIPracticeStepMatcher`、`ChordAttemptAccumulator` |
| 虚拟钢琴 | `VirtualPianoInputController` | `KeyContactDetectionService` |
| 真实琴手部 gate | `PracticeHandGateController` | `HandPianoActivityGate` |

matcher 只返回 reducer 需要的 typed outcome kind。不要重新增加未消费的 debug payload、source 标记、note set 副本或字符串解析分支。

用户 attempt 的条件：

- session 处于 guiding
- `acceptsPracticeAttempts == true`
- 不是 autoplay、manual replay 或 AI output
- event 属于当前 round generation

## 小节事实与进度

`PracticeAttemptReducer` 把 step attempt 聚合为 source-measure facts：

- 尝试次数与成功次数
- 当前 streak
- stable 状态
- 本轮最后一次 typed issue
- resume point

规则：

- streak 按手别、tempo 和本轮条件隔离。
- 同一小节发生错误后，后续单个正确 step 不能提前清除该轮错误。
- 已 stable 小节不会因未完成的新一轮局部尝试立即降级。
- passage stable 必须覆盖目标范围中的全部 source measure。
- loop 达到 `requiredSuccesses` 后结束，不开始额外一轮。

`PracticeProgressCoordinator` 防止旧曲目或旧 generation 的 load/save 覆盖当前 session。退出路径必须 await flush。

## 恢复

恢复过程：

```text
prepare score
-> load song history and resolve exact / historical / fresh / unavailable policy
-> session `applyLaunchRestorePolicy` 唯一入口
-> exact: load active configuration and resume point
-> historical: 当前曲谱整首 passage + 四项通用偏好，不写全局 defaults
-> fresh/unavailable: 当前曲谱整首、双手、100%、不循环与批准的成功目标
-> exact 的无效 passage/resume: 保留 measure facts，安装当前整首并立即 checkpoint 修复
-> exact valid 时 restore step index；其余从整首 first step 开始
-> remain ready/paused
```

policy 在 launch generation 与 ARGuide application ID 保护下传入 session。session replacement 在当前 revision 尚无进度时复用原 policy；一旦当前 session 已产生进度，先 flush 再按 exact 恢复，避免重新套用旧版本偏好而丢掉新事实。配置安装后 pending 与 active 一致，并统一刷新 active range、手别输入、autoplay timeline 与音频识别。无 policy 的旧 restore/apply 入口不存在。

恢复时不得：

- 自动 note-on
- 启动 sequencer
- 预览当前 step
- 接受输入 attempt

用户明确点击继续后才进入 guiding。

## 回放

`PracticePlaybackControlService` 使用 active range 和 tempo scale 构建当前片段的 playback timeline。踏板事件采用半开区间，不包含片段上界事件。

发声实现：

- `AVAudioSequencerPracticePlaybackService`：AVP 本地 sampler，需要 `SalC5Light2.sf2`。
- `CoreMIDIPracticePlaybackService`：发送到用户选择的外部 MIDI destination。

输出期间输入匹配保持抑制，避免回放反向推进练习。

## 正反馈

| 派生对象 | 来源 | 展示 |
| --- | --- | --- |
| feedback event | 当前 typed attempt | 顶部非模态 cue、空间恢复效果 |
| hotspot | 当前 passage 的 measure facts | 一个主要卡点 |
| next action | hotspot 与 round 状态 | 一个确定性操作 |
| round summary | active configuration + passage facts | 片段、手别、速度、结果和下一步 |
| measure map | durable facts | 未开始、练习中、稳定 |

反馈不保存到 JSON。相同 issue 的后续 attempt 通过事件序号区分，确保 UI 可以重新呈现。进入后台、换曲、restart、窗口关闭和 immersive dismiss 会立即失效 presentation。

## 录制与 take

- `RecordingTakeRecorder` 聚合 note/control events。
- `MIDIRecordingAdapter` 接收 MIDI 1.0/2.0。
- `RecordingTakeStore` 保存 `Documents/TakeLibrary/takes.json`。
- `TakePlaybackController` 回放 take。
- `RecordingMIDIExportService` 导出 `.mid`。

## 测试重点

- source/occurrence measure identity 与 repeat
- 单手 step 过滤与空 expected-note 边界
- active range 半开区间
- tempo、loop、required successes
- wrong/missing/incomplete chord outcome
- stable 状态与 streak
- A/B 曲目乱序恢复
- flush-before-teardown
- paused resume 静默
- feedback generation、重复事件和 lifecycle cleanup
- summary 与 measure map 只消费当前 passage facts

核心功能验证步骤见 [核心功能测试清单](../testing/core-function-checklist.md)。


## 启动与退出边界

曲库只登记 request；练习根视图在 active scene 激活它，只有 ready 才挂载 `PracticeStepView`。scene inactive 取消准备并 flush，但保留 request。显式返回或意外消失都由根视图的同一 operation 执行 generation 失效、full leave、immersive close/recover、prepared-song clear 与返回曲库；child view 不再维护第二套 leave。
