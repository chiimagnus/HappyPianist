# 数据流

本文只描述当前代码存在的运行链路。macOS 端不再包含 MIDI mapping、键盘注入或 AVP 的网络后端 client；visionOS 端（AVP）的 AI 即兴链路包含：

- 本地生成后端（CoreML / rule）
- 可选网络后端（Aria v2：Bonjour 发现 + HTTP `/generate` + WebSocket `/stream`，由 Mac 侧 `python_backend/aria_server/` 提供）

无论本地/网络后端，AVP 都严格只使用用户在 practice 设置中选择的后端（失败只提示，不自动降级/切换）。

## 主流程

| 流程 | 入口 | 关键对象 | 输出 |
| --- | --- | --- | --- |
| macOS MIDI 监听 | CoreMIDI source | `CoreMIDIInputService` -> `HappyPianistViewModel` | UI pressed notes、事件计数、录制输入 |
| macOS take 录制 | record button + MIDI note events | `DefaultRecordingService` | `RecordingTake` |
| macOS MIDI 导入 | `.mid` / `.midi` 文件 | `MIDIFileImporter` | take 列表中的导入 take |
| macOS 回放 | selected take | `RoutedMIDIPlaybackService` | 内建 sampler 或外部 MIDI destination |
| AVP 准备 | 钢琴类型选择 | `PracticeSetupState` + `WindowTransitionState` | 进入曲库前的 readiness gate |
| AVP 曲库 | bundled MusicXML / 用户导入 MusicXML | `SongLibraryViewModel` + `PracticePreparationService` | `PreparedPractice` |
| AVP 练习 | `PreparedPractice` + selected piano mode | `ARGuideViewModel` + `PracticeSessionViewModel` | 步骤推进、谱面、高亮、录制与回放 |
| AVP AI 即兴 | rolling note/CC context | `AIPerformanceService` + `ImprovBackendRegistry` | 连续评估、短窗生成、整形后送入可替换调度器（严格按所选后端） |

## macOS recorder

```mermaid
sequenceDiagram
  participant App as HappyPianistApp
  participant VM as HappyPianistViewModel
  participant MIDI as CoreMIDIInputService
  participant Rec as DefaultRecordingService
  participant Repo as SwiftDataRecordingTakeRepository
  participant Play as RoutedMIDIPlaybackService

  App->>VM: inject repository, MIDI input, playback, output service
  VM->>MIDI: startListening()
  MIDI-->>VM: MIDIEvent note/control updates
  VM->>Rec: append(event) when recording
  VM->>Repo: save(take) when recording stops
  VM->>Play: play(take, output)
```

录制数据最终写入 SwiftData store；回放可路由到 `AVSamplerMIDIPlaybackService` 或 `CoreMIDIOutputMIDIPlaybackService`。

## AVP 窗口与准备

```mermaid
flowchart TD
  A[preparation window] --> B[PianoTypePickerView]
  B --> C{selected PianoModeProtocol}
  C --> D[RealAudioPianoMode]
  C --> E[BluetoothMIDIPianoMode]
  C --> F[VirtualPianoMode]
  D --> G[CalibrationStepView]
  E --> H[BluetoothPianoPreparationView]
  F --> I[VirtualPianoPreparationView]
  G --> J[PracticeSetupState readiness]
  H --> J
  I --> J
  J --> K[library window]
  K --> L[practice window]
```

`HappyPianistAVPApp` 声明 `preparation`、`library`、`practice` 三个窗口和一个 `ImmersiveSpace`。窗口切换不依赖旧 `FlowState`；当前状态由 `PracticeSetupState` 与 `WindowTransitionState` 承载。

## AVP MusicXML 到练习

| 阶段 | 关键对象 | 结果 |
| --- | --- | --- |
| 导入/读取 | `SongLibraryViewModel`、`SongFileStore`、`MXLReader`、`BundledSongLibraryProvider` | MusicXML score |
| 乐谱归一化 | `MusicXMLPianoGrandStaffNormalizer`、`MusicXMLStructureExpander` | 面向钢琴练习的 score |
| 语义提取 | `MusicXMLTempoMap`、`MusicXMLPedalTimeline`、`MusicXMLFermataTimeline`、`MusicXMLAttributeTimeline`、`MusicXMLSlurTimeline`、`MusicXMLWordsSemanticsInterpreter` | timing、踏板、延音、表情信息 |
| 分手与 step | `MusicXMLHandRouter`、`PracticeStepBuilder`、`MusicXMLNoteSpanBuilder` | `PracticeStep[]`、note spans |
| 高亮与谱面 | `PianoHighlightGuideBuilderService`、`GrandStaffNotationLayoutService` | key guides、grand staff notation |
| session 注入 | `PracticeSessionViewModel` | 练习状态与 effect 队列 |

## AVP 输入源

| 模式 | 追踪模式 | 输入处理 | 说明 |
| --- | --- | --- | --- |
| 真实钢琴（音频） | `.practiceVirtualOrAudio` | `PracticeAudioRecognitionInputService` | 基于目标音的 harmonic template detector 推进 step。 |
| 真实钢琴（蓝牙 MIDI） | `.practiceBluetoothMIDI` | `PracticeMIDIInputService` | 使用 CoreMIDI MIDI 1.0/2.0 note-on 匹配 step；不启用手部按键 consumer。 |
| 虚拟钢琴 | `.practiceVirtualOrAudio` | `VirtualPianoInputController` + `KeyContactDetectionService` | 先放置 3D 88 键键盘，再用手部接触生成按键事件。 |

## BLE MIDI 输入链路

```mermaid
flowchart TD
  A[CoreMIDI source] --> B[BluetoothMIDIInputEventSourceService]
  B --> C[MIDI1MessageDecoder]
  B --> D[MIDI2MessageDecoder]
  C --> E[AsyncStream<MIDI1InputEvent>]
  D --> F[AsyncStream<MIDI2InputEvent>]
  E --> G[PracticeMIDIInputService]
  F --> G
  E --> H[MIDIRecordingAdapter]
  F --> H
  G --> I[MIDIPracticeStepMatcher]
  H --> J[RecordingTakeRecorder]
```

端点报告 MIDI 2.0 且 MIDI 2.0 input port 可用时订阅 MIDI 2.0，否则订阅 MIDI 1.0。调试日志带 `debugEventID` 和 source 归因，用于定位端点协议切换或事件丢弃。

## AI 即兴链路

practice 窗口的 settings popover 中可选择后端：

- `本地 CoreML（A.I. Duet / Performance RNN）`：AVP 端使用 CoreML 运行 Performance RNN 单步模型做自回归采样；模型文件（`AIDuetPerformanceRNN.mlpackage` / `AIDuetPerformanceRNN.mlmodelc`）不入库，由开发者本地放置并加入 Xcode target。
- `本地规则生成（Local rule）`：AVP 端直接调用内嵌 rule 引擎（seed 可复现）。
- `网络本地连接（Aria v2）`：AVP 通过 Bonjour 发现 `_lpduet._tcp` 服务并调用 HTTP `POST /generate` 获取 v2 events。
- `网络本地连接（Aria v2 Streaming）`：AVP 通过 Bonjour 获取 `ws_path` 并用 WebSocket `GET /stream` 接收 v2 chunk events（更快开声）。

```mermaid
sequenceDiagram
  participant AVP as AVP app
  participant Settings as Practice Settings
  participant Backend as ImprovBackendProtocol
  participant Engines as AVP rule engine
  participant Aria as Mac Aria v2 server

  Settings-->>AVP: selected ImprovBackendKind
  AVP->>Backend: generatePlaybackPlan(request)
  alt local CoreML duet (Performance RNN)
    Backend->>AVP: load step model from app bundle
    AVP-->>Backend: step model handle
    Backend-->>Backend: warmup + sampling loop (seeded)
    Backend-->>AVP: schedule
  else local rule
    Backend->>Engines: generate(notes, params, seed)
    Engines-->>Backend: generated notes
    Backend-->>AVP: schedule
  else network Aria v2
    Backend->>Aria: Bonjour resolve + HTTP/WS
    Aria-->>Backend: v2 events (notes + CC)
    Backend-->>AVP: schedule (built from events)
  end
```

本地规则生成由 AVP target 内嵌实现提供。当前默认后端为本地 CoreML；若未放置模型文件，UI 会提示缺失，并可手动切换到本地 rule。

## AVP 可恢复练习闭环（P1）

```mermaid
flowchart TD
  A[SongLibraryEntry UUID] --> B[PracticePreparationService actor]
  B --> C[PreparedPractice song identity + score revision]
  C --> D[PracticeSessionViewModel]
  D --> E[typed StepAttemptMatchResult]
  E --> F[PracticeAttemptReducer]
  F --> G[measure-level SongPracticeProgress]
  G --> H[PracticeProgressCoordinator]
  H --> I[FilePracticeProgressRepository]
  I --> J[Documents/Practice/progress-v1.json]
```

`PracticeStep` 是即时判定单位；持久化反馈以 source measure 为最小单位。重复结构使用 occurrence identity 定位本次播放位置，同时把学习事实聚合回 source measure。

配置分为长期默认值、下一轮 pending 配置和本轮 immutable active 配置。范围、手别、速度、循环和成功目标只在应用并重开一轮时进入 active state。恢复流程在 preparation 完成后加载完全匹配的 song UUID + score revision，应用片段和 step 位置后停在 `.ready`；只有用户明确开始后才进入 guiding 与发声。

窗口退出、场景进入非 active、session replacement 和完成一轮时遵循：停止新 attempt → flush 当前 generation → shutdown 输入/回放/录制 → 关闭 immersive。旧 generation 的延迟保存会被丢弃。

## P2 正反馈派生链路

```mermaid
flowchart LR
  A[typed user attempt] --> B[PracticeAttemptReducer]
  B --> C[durable measure facts]
  C --> D[one hotspot + one next action]
  B --> E[generation-safe feedback event]
  E --> F[non-modal cue]
  E --> G[piano-guide restoration effect]
  C --> H[round summary + measure map]
```

cue、summary、map 与空间效果都是 facts 的派生表现，不进入 progress JSON。Autoplay、manual replay、AI output、teardown 与 insufficient evidence 不发布反馈事件；旧 song/revision/round generation 的事件在 session 边界丢弃。
