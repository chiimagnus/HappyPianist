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

## 曲谱契约

`PracticePreparationService` 的正式输入是 MusicXML。可进入练习的 `PreparedPractice` 必须包含：

- stable song UUID 与 score revision
- `PracticeStep[]`
- `MusicXMLMeasureSpan[]`
- tempo、pedal、fermata 等时间线
- highlight guides
- notation 输入

不支持“有 steps、无小节”的兼容模式。新增非 MusicXML 来源前，应先定义新的产品模式和数据契约，而不是在现有 session 中添加 fallback。

`HappyPianistAVPTests/Fixtures/PracticeLearningLoopEightMeasures.musicxml` 是测试 fixture，不是产品内置曲目。

## 配置与范围

一轮练习的配置包含：

- passage
- hand mode
- tempo scale
- loop enabled
- required successes

设置先写入 pending configuration；应用或 restart 时生成新的 active configuration。本轮开始后 active configuration 不可变。

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
-> match song UUID + score revision
-> load active configuration and resume point
-> resolve active range
-> restore step index
-> remain ready/paused
```

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

完整 Apple target 命令见 [../testing/practice-learning-loop-p1-checklist.md](../testing/practice-learning-loop-p1-checklist.md)。
