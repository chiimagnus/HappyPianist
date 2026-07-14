# 数据流

本文只描述当前存在的 visionOS 运行链路。

## 主流程

| 流程 | 入口 | 关键对象 | 输出 |
| --- | --- | --- | --- |
| 准备 | 钢琴模式选择 | `PracticeSetupState`、`PianoModeProtocol` | readiness gate |
| 曲库 | bundled / 用户导入 MusicXML | `SongLibraryBootstrapLoader`、`SongLibraryViewModel`、`SongFileStore` | `SongLibraryEntry` |
| 曲谱准备 | 曲库中切换唱片 | `SongLibraryViewModel`、`PracticePreparationService` | 右侧 Ornament 的 loading / ready / failure 状态 |
| 练习 | prepared score + piano mode | `ARGuideViewModel`、`PracticeSessionViewModel` | 导航、判定、回放、录制 |
| 持久化 | attempt 与 session 生命周期 | reducer、coordinator、repository | 小节事实与恢复点 |
| 正反馈 | durable facts + typed attempt | feedback policies / view models | cue、summary、map、空间效果 |
| AI 对弹 | rolling context | `AIPerformanceService`、`ImprovBackendRegistry` | playback schedule |

## 窗口与准备

```mermaid
flowchart TD
  A[preparation window] --> B[PianoTypePickerView]
  B --> C{PianoModeProtocol}
  C --> D[RealAudioPianoMode]
  C --> E[BluetoothMIDIPianoMode]
  C --> F[VirtualPianoMode]
  D --> G[Calibration]
  E --> H[Calibration + MIDI Source]
  F --> I[Virtual Piano Placement]
  G --> J[PracticeSetupState Ready]
  H --> J
  I --> J
  J --> K[library window]
  K --> L[practice window]
  L --> M[mixed ImmersiveSpace]
```

`WindowTransitionState` 维护 preparation、library、practice 三个窗口的替换式切换。ARKit provider 只在沉浸空间内启动，并由 `ARTrackingRequirements` 按校准、练习模式和虚拟琴摆放阶段选择 hand、world 与 horizontal-plane provider。scenePhase 进入非 active 时停止 session 与所有消费者，恢复 active 后从当前业务状态重新推导需求。

## MusicXML 导入与准备

### 启动与导入

```text
SongLibraryView.task
-> SongLibraryViewModel.loadLibraryIfNeeded
-> SongLibraryBootstrapLoader actor
-> bundled scan + index decode off MainActor
-> one immutable bootstrap snapshot
```

```text
LibraryWindowView / SongLibraryView
-> SongLibraryViewModel.importMusicXML
-> SongFileStore
-> Documents/SongLibrary/scores
-> SongLibraryIndexStore
```

当前没有第二套 MusicXML import service。`.mxl` 在 preparation 阶段通过 `MXLReader` 解包。

### 准备管线

| 阶段 | 关键对象 | 产物 |
| --- | --- | --- |
| 读取 | `SongLibraryViewModel`、`BundledSongLibraryProvider` | score URL |
| 解析 | `MusicXMLParser`、`MXLReader` | score model |
| 钢琴归一化 | `MusicXMLPianoGrandStaffNormalizer` | 双谱表结构 |
| 展开 | `MusicXMLStructureExpander` | repeat / ending 后的 occurrence 序列 |
| 时间语义 | tempo、pedal、fermata、attribute、slur timelines | 回放和谱面上下文 |
| 分手与 step | `MusicXMLHandRouter`、`PracticeStepBuilder` | `PracticeStep[]` |
| 小节身份 | `MusicXMLMeasureSpan`、`PracticeMeasureIndex` | source / occurrence 映射 |
| 高亮与谱面 | guide builder、notation layout | 键位 guide 与五线谱输入 |
| session 注入 | `PracticeSessionViewModel` | 可开始的一轮练习 |

正式 preparation 结果必须同时有可演奏 steps 和 measure spans。解析失败或缺少小节结构时应返回具体错误，不进入推测性的兼容模式。

曲库选择链路：

```text
选择唱片
-> 取消旧 preparation generation
-> 右侧 Ornament 显示系统骨架占位
-> 准备并恢复精确 song UUID + revision 的进度
-> 展示小节地图与 pending configuration
-> 用户点击“去练习！”
-> 配置有修改时应用 pending；未修改时保留恢复位置
-> 打开 practice window
```

切换唱片会丢弃尚未开始的草稿设置；重新选回曲目时从持久化进度或整首、双手、100%、不循环的默认值重建。曲库主内容保留曲名、作曲家与试听控件，练习信息只在 trailing Ornament 中呈现。

## 本轮配置与 active range

```text
UserDefaults defaults
-> pending PracticeRoundConfiguration
-> apply / restart
-> immutable active configuration
-> PracticeActiveRange
```

active range 同时约束：

- step 导航
- 当前谱面视口
- 琴键高亮
- autoplay
- manual replay
- 一轮完成边界

手别、速度、循环和成功目标只在应用 pending 配置并开始新一轮时生效。

## 输入与 typed attempt

| 模式 | 输入链路 | 判定 |
| --- | --- | --- |
| 真实钢琴（音频） | microphone -> recognition service -> accumulator | 目标音证据与 typed outcome |
| 真实钢琴（蓝牙 MIDI） | CoreMIDI -> bounded MIDI1/2 stream -> decoder -> input service | deterministic note/chord matching |
| 虚拟钢琴 | newest-only `FingerTipsSnapshot` -> indexed hand contact -> virtual input controller | 虚拟按键 note events |

手部 producer 只发布 typed snapshot；琴键几何变化时重建一次 hit-test index，每帧仅查询相邻候选键。CoreMIDI 缓冲溢出会发布 All Notes Off，统一复位 matcher、AI 持音上下文和录音中的开放音符。自动播放、手动回放、AI 输出、paused、suspended 与非 guiding 状态不会生成用户 attempt。

## 练习事实与恢复

```mermaid
flowchart LR
  A[typed user attempt] --> B[PracticeAttemptReducer]
  B --> C[MeasurePracticeFact]
  C --> D[SongPracticeProgress]
  D --> E[PracticeProgressCoordinator]
  E --> F[FilePracticeProgressRepository]
  F --> G[Documents/PracticeProgress/progress-v1.json]
```

规则：

- `PracticeStep` 是即时判定单位。
- source measure 是持久化学习单位。
- occurrence identity 只负责重复结构中的播放位置。
- streak 按手别、速度与本轮条件隔离。
- resume point 保存片段、配置与当前 step。
- 恢复完成后停在 ready/paused，不自动发声。
- back、background、换 session 与完成时等待 flush。

## 正反馈

```mermaid
flowchart LR
  A[typed attempt] --> B[Feedback Event]
  C[Measure Facts] --> D[Hotspot Policy]
  D --> E[One Next Action]
  B --> F[Non-modal Cue]
  B --> G[RealityKit Restoration Effect]
  C --> H[Round Summary]
  C --> I[Measure Map]
```

反馈是事实的派生表现：

- 一次只选择一个主要卡点和一个下一步。
- 无证据时不制造问题。
- cue、summary、map 与空间效果不写入 progress JSON。
- 换曲、restart、进入后台、关闭窗口和退出沉浸空间会清理反馈 presentation。

## 录制与回放

蓝牙 MIDI 与虚拟键事件可进入：

```text
MIDIRecordingAdapter
-> RecordingTakeRecorder
-> RecordingTakeStore
-> Documents/TakeLibrary/takes.json
```

`TakePlaybackController` 复用 sequencer 回放；`RecordingMIDIExportService` 导出 `.mid`。

## AI 对弹

后端由 `practiceImprovBackendKind` 选择：

- 本地规则：`LocalRuleImprovBackend`
- 本地 CoreML：`LocalCoreMLDuetImprovBackend`
- Aria v2 HTTP：Bonjour + `POST /generate`
- Aria v2 Streaming：Bonjour + WebSocket `/stream`

```mermaid
sequenceDiagram
  participant Session as Practice Session
  participant Service as AIPerformanceService
  participant Registry as ImprovBackendRegistry
  participant Backend as Selected Backend
  participant Queue as DuetAIPlaybackQueue

  Session->>Service: rolling note/CC context
  Service->>Registry: resolve selected backend
  Registry-->>Service: backend
  Service->>Backend: generate request
  Backend-->>Service: events / schedule input
  Service->>Queue: shaped playback plan
```

后端失败只更新状态并停止该次生成，不自动降级到另一个后端，也不写入练习进度。


## 诊断事件与导出

```text
Typed domain failure
-> DiagnosticEvent
-> AppDiagnosticsReporter
   -> OSLogDiagnosticsSink
   -> FileDiagnosticsStore（仅 exportable）
```

曲谱准备失败使用同一个 `LibraryPracticePreparationFailure` 生成右侧错误界面、默认展开且可选择复制的技术详情，以及诊断事件。事件写入导出存储成功后，界面才显示“此错误已写入诊断日志”。重试会生成新的事件 ID，不复用旧失败。

用户通过曲库顶部“诊断”入口管理日志。导出动作在本地生成 ZIP，不自动上传。日志默认保留7 个日历日，并排除绝对路径、原始 MusicXML、逐音 MIDI、音频样本、手部帧、AI 正文和凭据。
