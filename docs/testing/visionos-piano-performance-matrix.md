# visionOS Simulator 钢琴演奏全链路矩阵

这是自动化覆盖地图，不是能力通过声明。表中每一项只有附上对应 `xcodebuild test` 运行日志后，才可在测试记录中标为 Pass；本文件不保存临时运行结果。

## 运行

先列出可用 destination：

```bash
make destinations
```

选择实际的 visionOS Simulator ID 后运行完整测试：

```bash
xcodebuild test \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP \
  -destination 'platform=visionOS Simulator,id=<device-id>' \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO
```

记录时至少保留日期、Xcode、visionOS Simulator 名称和 ID、提交 SHA、命令与完整结果。`build-for-testing` 不是通过证据。

## 自动化矩阵

| 链路 | 现有自动化入口 | Simulator 可验证的边界 | 运行日志 |
| --- | --- | --- | --- |
| MusicXML 准备、performed order、steps 与小节 | `PracticePreparationIdentityTests`、`PracticePreparationCancellationTests`、`ProfessionalCorpusScoreSnapshotTests` | 解析、规范化、结构展开、演奏计划与 projection 一致性 | 未记录 |
| playback、active range、seek 与 loop | `AutoplayPerformanceTimelineTests`、`PlaybackSequenceBuilderTests`、`PracticePlaybackCoordinatorTests`、`ProfessionalCorpusPerformanceSnapshotTests` | event ID、顺序、range 重建、loop 收尾与 app/CoreMIDI sequence 一致性 | 未记录 |
| MIDI fake 与 transport reset | `CoreMIDIPracticePlaybackServiceStopTests`、`MIDI2ValueMappingTests` | generation guard、timestamp、controller、stop/reset 与断连后旧事件隔离 | 未记录 |
| 音频失败与恢复 | `PracticeSequencerPlaybackServiceProtocolTests`、`PracticePlaybackCoordinatorTests` | load/render 失败、识别抑制窗口、状态恢复与无残留发声 | 未记录 |
| hand tracking 生命周期 | `VirtualPianoInputControllerTests`、`HandPianoActivityGateTests`、`PerformanceObservationConfusionMatrixTests` | contact 生命周期、校准版本、tracking loss、unknown/insufficient 与重复触键 | 未记录 |
| recording 与 session 生命周期 | `PracticeSessionRecorderTests`、`RecordingTakeStoreTests`、`PracticeLaunchLifecycleTests` | generation、checkpoint、持久化边界、恢复与原始观察不写入进度 | 未记录 |
| alignment | `PerformanceAlignmentTests`、`PerformanceObservationConfusionMatrixTests` | occurrence identity、missing/extra/ambiguous/unknown、输入 capability 分层 | 未记录 |
| assessment | `PerformanceAssessmentTests`、`PracticeLearningLoopIntegrationTests` | pitch、timing、duration、dynamics、voicing 与 pedal 的证据状态 | 未记录 |
| coaching | `PracticeCoachingDecisionTests`、`PracticeHistoricalPreferencesApplicationTests` | 单一动作、accept/skip、范围与 completion remeasure | 未记录 |
| AI 输入与输出生命周期 | `AIPerformanceCoordinatorTests`、`DuetOutOfOrderResponseTests`、`DuetDisableTeardownTests`、`DuetParallelInputWhilePlaybackTests` | 取消、乱序响应、generation 隔离和 teardown | 未记录 |

## 不在此矩阵中通过

Simulator 不证明真实 MIDI、麦克风、手部追踪、音频 onset、路由恢复或钢琴演奏听感。这些需要真机、钢琴家与其他证据 gate；在相应协议实际执行前，相关能力保持 pending。
