# 架构

## 系统上下文
LonelyPianist 由三条运行面组成：macOS 负责 MIDI 输入采集、映射、录音和 Dialogue 编排；visionOS 负责曲库、校准、空间追踪和 AR 练习引导；Python 负责本地 Piano Dialogue 推理。当前仓库未包含 GitHub Actions workflows，测试与格式化均以本地手动运行为准。

## 运行时边界
| 运行单元 | 位置 | 生命周期 | 核心职责 | 验证入口 |
| --- | --- | --- | --- | --- |
| macOS app | `LonelyPianist/` | App 启动到关闭 | MIDI、映射、录音、对话、SwiftData | 本地 `xcodebuild test`（macOS） |
| visionOS app | `LonelyPianistAVP/` | 3×Window + ImmersiveSpace | 校准、曲库、追踪、练习、贴皮高亮提示 | 本地 `xcodebuild test`（visionOS simulator） |
| Dialogue server | `piano_dialogue_server/server/` | uvicorn 进程 | HTTP `/generate` + WS `/ws` 协议、Bonjour 广播、推理、调试包、MIDI 上传扩展 | Python smoke scripts + curl |
| 本地验证 | 本机 `xcodebuild` / python scripts | 手动触发 | 回归测试与 smoke | `testing.md` |

## 组件边界
| 组件 | 输入 | 输出 | 修改热点 |
| --- | --- | --- | --- |
| `LonelyPianistViewModel` | MIDI / UI / repo 状态 | mapping / recorder / dialogue / logs | `handleMIDIEvent` |
| `CoreMIDIInputService` | CoreMIDI event list | `MIDIEvent` callback + connection state | source refresh、MIDI 1.0/2.0 解码 |
| `DialogueManager` | phrase notes / silence | WS 请求、AI take、状态 | `start`, `handle`, `playAIReply` |
| `AppState` | tracking runtime、校准存取、沉浸空间状态 | providers 状态 + runtime calibration | `resolveRuntimeCalibrationFromTrackedAnchors` |
| `FlowState` | 钢琴类型与曲目/steps | 当前流程状态 | `setImportedSteps`, `clearSongAndSteps` |
| `WindowCoordinator` | 窗口导航意图（去曲库/去练习/回到类型选择） | 记录 `pendingTransition(from,to)`，并承载 `resetToPreparation` 的 flow 清理策略 | `beginTransition`, `consumePendingTransition`, `resetToPreparation` |
| `PianoModeRegistryService` | `[any PianoModeProtocol]` + id 查找 | 模式列表与查找 | 新增模式时需注册；修改 `PianoModeProtocol` 影响所有模式实现 |
| `BluetoothMIDIInputEventSourceService` | CoreMIDI UMP（MIDI 1.0/2.0） | `AsyncStream<PracticeInputEvent>` | MIDI 1.0/2.0 解码、source 刷新、事件过滤 |
| `MIDIRecordingAdapter` | `PracticeInputEvent` + `RecordingTakeRecorder` | take 事件落盘 | 桥接事件类型、CC/pitch bend 映射 |
| `RecordingTakeStore` | `RecordingTake` JSON | `Documents/TakeLibrary/takes.json` | JSON 编解码、原子写入 |
| `TakePlaybackController` | `RecordingTake` + sequencer | take 回放控制 | seek/cache/pause 语义 |
| `SongLibraryViewModel` | fileImporter URLs | index + score/audio 存储 | 导入 / 删除 / 试听 |
| `ARGuideViewModel` | immersive state + providers | localization state | open / locate / retry |
| `BonjourBackendDiscoveryService` | mDNS browse results | resolved host/port 或 denied/failed | `start`, `resolveHostPort` |
| `ImprovBackendClient` | HTTP `GenerateRequest` | `ResultResponse` / error | URL 构造、解码与错误映射 |
| `PhraseRecorder` | note on/off + 时间 | phrase notes（用于后端输入） | 录制窗口与边界条件 |
| `MusicXMLPianoGrandStaffNormalizer` | `MusicXMLScore`（双 part 钢琴谱） | normalized `MusicXMLScore`（合并为单 part + staff=1/2） | 仅处理恰好 2 part 且各自单谱号的情况 |
| `MusicXMLHandRouter` | `MusicXMLScore`（可能缺失 staff） | routed `MusicXMLScore`（单谱表自动补 staff=1/2） | 阈值策略、只对单谱表生效的边界 |
| `PracticeSessionViewModel` | finger tips / MIDI events + steps（含左右手） | matching / autoplay / notation context | `handleFingerTipPositions`、按手分别匹配的 gate |
| `PianoGuideOverlayController` | `PracticeStep`, `PianoKeyboardGeometry` | RealityKit 贴皮高亮实体 | key-top decal、`KeyDecalSoftRect`、keyboard-local transform |
| `GrandStaffNotationLayoutService` | `PianoHighlightGuide[]` + measure spans + context | `GrandStaffNotationLayout`（双谱表 items + barlines） | staff routing、x/y 坐标映射、可读性与性能 |
| `GazePlaneHitTestService` | gaze ray + planes | `PlaneHit?` | 命中选择策略与阈值 |
| `GazePlaneDiskConfirmationViewModel` | `PlaneHit` + palm centers | progress + confirmed | 抗抖动阈值、确认时序 |
| `VirtualKeyboardPoseService` | plane pose + hand center + device pose | `worldFromKeyboard` | 键盘朝向与中心对齐 |
| `VirtualPianoKeyGeometryService` | `KeyboardFrame` | 88 键 `PianoKeyboardGeometry` | `generateKeyboardGeometry` |
| `KeyContactDetectionService` | finger tips + geometry | 按键 started/ended/down（迟滞） | `detect` |
| `VirtualPianoOverlayController` | `PianoKeyboardGeometry` | RealityKit 3D 键盘 | `update` |

## 依赖方向
```mermaid
flowchart LR
  subgraph macOS
    A[CoreMIDIInputService] --> B[LonelyPianistViewModel]
    B --> C[DefaultMappingEngine]
    B --> D[DialogueManager]
    B --> E[DefaultRecordingService]
    D --> F[WebSocketDialogueService]
    D --> G[RoutedMIDIPlaybackService]
  end

  subgraph visionOS
    APP[LonelyPianistAVPApp] --> CO[WindowCoordinator]
    CO --> FS[FlowState]
    CO --> PMR[PianoModeRegistryService]
    APP --> PW[PreparationWindowRootView]
    APP --> LW[LibraryWindowRootView]
    APP --> PRW[PracticeWindowRootView]
    LW --> J[SongLibraryViewModel]
    PRW --> K[ARGuideViewModel]
    K --> AS[AppState]
    AS --> L[ARTrackingService]
    K --> M[PracticeSessionViewModel]
    K --> BD[BonjourBackendDiscoveryService]
    K --> IC[ImprovBackendClient]
    M --> N[PianoGuideOverlayController]
    M --> W[KeyContactDetectionService]
    M --> X[VirtualPianoOverlayController]
    M --> BLE[BluetoothMIDIInputEventSourceService]
    M --> RA[RecordingTakeRecorder]
    K --> Y[VirtualPianoKeyGeometryService]
    J --> O[SongLibraryIndexStore]
    J --> P[SongFileStore]
    J --> NORM[MusicXMLPianoGrandStaffNormalizer]
    NORM --> MHR[MusicXMLHandRouter]
  end

  subgraph Python
    QB[Bonjour broadcaster] --> Q[FastAPI /generate + /ws]
    Q --> R[Strategy router]
    R --> E1[model engine]
    R --> E2[deterministic engine]
    R --> E3[rule engine]
  end

  D <-->|WS /ws generate| Q
  BD <-->|mDNS browse| QB
  IC -->|HTTP /generate| Q
  K --> M
```

## GitHub Actions 架构
当前仓库未包含 `.github/workflows/`，因此没有 PR 自动测试或格式化工作流；所有验证以本地 `xcodebuild test` 和 Python smoke scripts 为准（见 `testing.md`）。

## 关键契约
| 契约 | 位置 | 作用 |
| --- | --- | --- |
| `DialogueNote` / `GenerateRequest` / `ResultResponse` | Swift + Python | 对话请求和结果 |
| `MappingConfigPayload` | macOS models | 映射编辑和执行 |
| `SongLibraryIndex` / `SongLibraryEntry` | AVP models | 曲库索引 |
| `StoredWorldAnchorCalibration` | AVP models | 校准持久化 |
| `PracticeStep` / `PracticeStepNote` | AVP models | 练习数据 |
| `ScoreHand` | AVP models | 左右手语义（由 staff 推导；贯穿 step/guide/高亮/判定） |
| `PracticeInputEvent` | AVP models | BLE MIDI 练习输入事件（G1 channel voice） |
| `RecordingTake` / `RecordingTakeEvent` | AVP models | Take 录制产物（事件列表 + 元数据） |
| `PianoModeProtocol` | AVP services | 钢琴模式能力契约（id、卡片、准入、工厂） |
| `DataProviderState` | AR tracking | provider 可用性 |
| `GrandStaffNotationLayout` / `GrandStaffNotationContext` | AVP models | 双谱表五线谱渲染契约（上下谱表 + barline + context） |

## 扩展点
- macOS：可在 `RoutedMIDIPlaybackService` 下扩展回放后端。
- AVP：可扩展曲库索引字段、校准算法、练习匹配策略、RealityKit 贴皮高亮表现和虚拟钢琴交互模式。
- Python：可扩展请求参数、采样策略和调试包字段。
- 自动化（未来若引入）：可把 Python smoke tests 接入 CI，并按需拆分 AVP 测试为 `build-for-testing` + 完整 `test`。

## 危险修改区
| 区域 | 风险 | 必跑验证 |
| --- | --- | --- |
| `LonelyPianistViewModel.handleMIDIEvent` | 映射、录音、Dialogue 同时受影响 | macOS tests |
| `DialogueManager.startGeneration / playAIReply` | 本地服务协议和回放状态可能漂移 | macOS tests + Python smoke |
| `CoreMIDIInputService` | Swift 6.2 捕获规则、CoreMIDI source 生命周期 | macOS tests |
| `AppState.resolveRuntimeCalibrationFromTrackedAnchors` | Step 3 定位失败 | AVP tests + 手工校准 |
| `SongLibraryViewModel.importMusicXML / deleteEntry / bindAudio` | 曲库 index 和文件副本漂移 | AVP library tests |
| `MusicXMLHandRouter.routeIfNeeded` | 单谱表 staff/左右手路由漂移，影响五线谱/高亮/判定 | AVP tests + 手工导入验证 |
| `PracticeSessionViewModel.startAutoplayTaskIfNeeded` | 自动演奏、step 推进联动 | AVP practice tests |
| `AudioStepAttemptAccumulator.evaluateHandSeparated` / `ChordAttemptAccumulator.registerHandSeparated` | “按手分别满足”语义漂移（音频/MIDI/press 三输入必须一致） | AVP practice tests |
| `PianoGuideOverlayController.updateHighlights` | 贴皮位置、大小、材质、生命周期 | AVP tests + Vision Pro 手工观察 |
| `GrandStaffNotationLayoutService.makeLayout` | 五线谱渲染错位、staff 分配错误、性能退化 | AVP tests + 手工观察 |
| `KeyContactDetectionService.detect` | 迟滞阈值、黑键优先、started/ended delta | VirtualPianoTests + Vision Pro 手工验证 |
| `ARGuideViewModel.updateGazePlaneDiskGuidance` | 平面命中/确认阈值/WorldAnchor 复用导致键盘漂移 | AVP tests + 真机放置验证 |
| `piano_dialogue_server/server/engines/model_inference.py::_patch_safe_logits` | 推理结果和异常恢复 | Python smoke scripts |

## Coverage Gaps
- 没有三端端到端自动化门禁；当前依赖单元测试 + 手工冒烟组合覆盖。
- Python 服务仍需本地启动与脚本验证。
- AVP 的手部追踪/平面检测/视觉舒适度必须真机验证。
