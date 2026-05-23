# 数据流

本文只描述当前代码存在的运行链路。macOS 端不再包含 MIDI mapping、键盘注入或 Dialogue client；visionOS 端（AVP）的 AI 即兴链路支持 **本地生成后端**（Swift）与 **可选网络后端**（本机 Python 服务），并且严格只使用用户在 practice 设置中选择的后端（不会自动降级/切换）。

## 主流程

| 流程 | 入口 | 关键对象 | 输出 |
| --- | --- | --- | --- |
| macOS MIDI 监听 | CoreMIDI source | `CoreMIDIInputService` -> `LonelyPianistViewModel` | UI pressed notes、事件计数、录制输入 |
| macOS take 录制 | record button + MIDI note events | `DefaultRecordingService` | `RecordingTake` |
| macOS MIDI 导入 | `.mid` / `.midi` 文件 | `MIDIFileImporter` | take 列表中的导入 take |
| macOS 回放 | selected take | `RoutedMIDIPlaybackService` | 内建 sampler 或外部 MIDI destination |
| AVP 准备 | 钢琴类型选择 | `PracticeSetupState` + `WindowTransitionState` | 进入曲库前的 readiness gate |
| AVP 曲库 | bundled MusicXML / 用户导入 MusicXML | `SongLibraryViewModel` + `PracticePreparationService` | `PreparedPractice` |
| AVP 练习 | `PreparedPractice` + selected piano mode | `ARGuideViewModel` + `PracticeSessionViewModel` | 步骤推进、谱面、高亮、录制与回放 |
| AVP AI 即兴 | recorded phrase / selected clip | `AIPerformanceService` + `ImprovBackendRegistry` | 生成片段并排程回放（严格按所选后端） |
| Python 生成（可选） | HTTP / WebSocket request | FastAPI + rule / deterministic / model engine | 仅当选择 `网络本地连接` 后端时触发 |

## macOS recorder

```mermaid
sequenceDiagram
  participant App as LonelyPianistApp
  participant VM as LonelyPianistViewModel
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

`LonelyPianistAVPApp` 声明 `preparation`、`library`、`practice` 三个窗口和一个 `ImmersiveSpace`。窗口切换不依赖旧 `FlowState`；当前状态由 `PracticeSetupState` 与 `WindowTransitionState` 承载。

## AVP MusicXML 到练习

| 阶段 | 关键对象 | 结果 |
| --- | --- | --- |
| 导入/读取 | `MusicXMLImportService`、`MXLReader`、`BundledSongLibraryProvider` | MusicXML score |
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

- `网络本地连接`：通过 Bonjour 发现 + HTTP 请求调用本机 `piano_dialogue_server`（电脑端运行）。
- `本地 deterministic（Local deterministic）`：AVP 端直接调用 SwiftPM `ImprovEngines`（seed 可复现）。
- `本地规则生成（Local rule）`：AVP 端直接调用 SwiftPM `ImprovEngines`（seed 可复现）。
- `按谱片段回放（tick-range replay）`：不做生成，回放当前谱面片段；它不是自动 fallback，只会在用户选择时使用。

```mermaid
sequenceDiagram
  participant AVP as AVP app
  participant Settings as Practice Settings
  participant Backend as ImprovBackendProtocol
  participant Engines as ImprovEngines (SwiftPM)
  participant Bonjour as BonjourBackendDiscoveryService
  participant API as piano_dialogue_server

  Settings-->>AVP: selected ImprovBackendKind
  AVP->>Backend: generatePlaybackPlan(request)
  alt local deterministic / local rule
    Backend->>Engines: generate(notes, params, seed)
    Engines-->>Backend: generated notes
    Backend-->>AVP: schedule
  else network bonjour http
    Backend->>Bonjour: discover _lonelypianist._tcp.local.
    Bonjour-->>Backend: host, port, path=/generate
    Backend->>API: POST /generate
    API-->>Backend: ResultResponse
    Backend-->>AVP: schedule
  else tick-range replay
    Backend-->>AVP: tickRange(maxMeasures)
  end
```

Python 后端的 `GenerateParams.strategy` 仅支持 `model`；`deterministic` / `rule` 已迁移到 SwiftPM（`Packages/ImprovEngines/`），仅用于 AVP 端的本地生成路径。
