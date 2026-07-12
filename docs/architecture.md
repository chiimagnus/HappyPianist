# 架构

## 系统上下文

```mermaid
flowchart LR
  XML[MusicXML / MXL] --> LIB[Song Library]
  LIB --> PREP[PracticePreparationService]
  PREP --> SESSION[PracticeSessionViewModel]

  MIC[Microphone] --> SESSION
  MIDI[Bluetooth MIDI] --> SESSION
  VPIANO[Virtual Piano] --> SESSION

  SESSION --> PLAY[Playback / Recording]
  SESSION --> PROGRESS[Practice Progress]
  SESSION --> FEEDBACK[Feedback / Summary / Map]
  SESSION --> IMMERSIVE[RealityKit Overlays]

  SESSION --> AI[ImprovBackendRegistry]
  AI --> LOCAL[Local Rule / CoreML]
  AI -->|optional| ARIA[Mac Aria v2 Server]
```

## 运行时边界

| 单元 | 位置 | 核心职责 |
| --- | --- | --- |
| visionOS App | `HappyPianistAVP/` | 三窗口流程、沉浸空间、曲库、练习、录制与 AI 对弹。 |
| visionOS Tests | `HappyPianistAVPTests/` | 业务逻辑和 Apple target 集成测试。 |
| RealityKit 内容包 | `Packages/RealityKitContent/` | Reality Composer Pro 资产和 bundle。 |
| Python 服务（可选） | `python_backend/` | Aria v2 推理、Bonjour、HTTP/WS 与 smoketest。 |

## App 依赖图

```mermaid
flowchart TD
  APP[HappyPianistAVPApp] --> STATE[AppState]
  STATE --> SETUP[PracticeSetupState]
  STATE --> WINDOW[WindowTransitionState]
  STATE --> LIBRARY[SongLibraryViewModel]
  STATE --> ARGUIDE[ARGuideViewModel]
  STATE --> MODES[PianoModeRegistryService]

  LIBRARY --> FILES[SongFileStore]
  LIBRARY --> INDEX[SongLibraryIndexStore]
  LIBRARY --> PREP[PracticePreparationService]

  PREP --> PARSER[MusicXMLParser]
  PREP --> EXPAND[MusicXMLStructureExpander]
  PREP --> HANDS[MusicXMLHandRouter]
  PREP --> STEPS[PracticeStepBuilder]
  PREP --> GUIDES[PianoHighlightGuideBuilderService]

  ARGUIDE --> SESSION[PracticeSessionViewModel]
  SESSION --> INPUT[Audio / MIDI / Virtual Input]
  SESSION --> PLAYBACK[Playback Services]
  SESSION --> PROGRESS[PracticeProgressCoordinator]
  SESSION --> FEEDBACK[Feedback Policies]
```

`AppState.configureLiveAppGraphIfNeeded()` 是 live app 的 composition root。新增服务必须在创建它的 task 中完成注入和消费；不要留下未接入的协议或实现。

## 窗口与空间

`HappyPianistAVPApp` 声明：

- `preparation` window
- `library` window
- `practice` window
- mixed `ImmersiveSpace`

`WindowTransitionState` 负责替换式窗口切换。`ARGuideViewModel` 协调沉浸空间、追踪、练习 session、录制与 AI 服务。

## 主要领域边界

| 边界 | 核心类型 | 说明 |
| --- | --- | --- |
| 曲库 | `SongLibraryEntry`、`SongLibraryIndex` | bundled 与用户导入曲目的统一索引。 |
| 曲谱准备 | `PreparedPractice`、`PracticePreparationService` | MusicXML 到 steps、measure spans、timelines、guide 与 notation 输入。 |
| 练习配置 | `PracticeRoundConfigurationController` | pending 与 active round configuration。 |
| 范围 | `PracticeMeasureIndex`、`PracticeActiveRange` | 小节、step、回放、谱面和完成边界的统一投影。 |
| 判定 | `StepAttemptMatchResult`、matcher/accumulator | 输入证据转换为 typed attempt outcome。 |
| 进度 | `SongPracticeProgress`、`PracticeProgressCoordinator` | 小节级事实、恢复点、generation-safe 保存。 |
| 反馈 | feedback policies、view models | 从 durable facts 派生 cue、summary、map 和空间效果。 |
| 录制 | `RecordingTakeRecorder`、`RecordingTakeStore` | 练习中的 MIDI 风格事件记录、回放与导出。 |
| AI | `ImprovBackendRegistry`、`AIPerformanceService` | 严格使用用户选择的本地或网络后端。 |

## 关键不变量

- 正式曲谱来源是 MusicXML；可进入练习的 prepared result 必须同时有 steps 与 measure spans。
- `PracticeStep` 是即时判定单位；持久化事实聚合到 source measure。
- 重复结构用 occurrence identity 定位播放位置，用 source identity 汇总学习事实。
- 本轮 active configuration 在一轮中不可变；设置修改只影响下一轮。
- 退出、后台、换 session 与完成流程必须先停止新 attempt，再 flush 进度，最后 teardown 输入和回放。
- feedback 表现不进入 progress JSON。
- AI 失败不改变练习进度，也不自动切换后端。

## 高风险修改区

| 区域 | 风险 | 最低验证 |
| --- | --- | --- |
| `PracticePreparationService` | parser、repeat、手别、tempo、guide 与 identity 全链路 | MusicXML + preparation tests |
| `PracticeSessionViewModelCommands` | range、resume、round、completion 与 feedback 生命周期 | session + progress + feedback tests |
| `PracticeAttemptReducer` | streak、稳定状态与错误事实 | reducer tests |
| `PracticeProgressCoordinator` | 乱序 load/save、flush 与跨曲污染 | delayed repository tests |
| `PracticePlaybackControlService` | tempo、片段边界、pedal 与输入抑制 | playback/autoplay tests |
| MIDI/audio matcher | 错音、漏音、和弦与证据不足 | matcher tests |
| `ARGuideViewModel` / `ImmersiveView` | scenePhase、tracking 和 overlay 清理 | Simulator + Vision Pro |
| `SongLibraryViewModel` | 导入、删除、revision、继续练习与换曲 | library + preparation tests |

## 验证分层

1. 纯 Swift：模型、reducer、range、matcher、repository、policy。
2. Xcode target：完整类型检查、资源、SwiftUI、RealityKit、AVFoundation、CoreMIDI 集成。
3. Simulator / Vision Pro：窗口、生命周期、声音、MIDI、手部追踪、空间对齐与舒适度。
