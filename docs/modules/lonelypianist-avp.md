# 模块：LonelyPianistAVP

## 边界
- 负责：Step 1 校准、Step 2 曲库、Step 3 练习、沉浸空间和手部追踪。
- 不负责：macOS MIDI 映射和 Python 推理。

## 目录地图
| 路径 | 角色 |
| --- | --- |
| `AppState.swift` | tracking/runtime calibration/沉浸空间状态枢纽 |
| `Models/AppFlow/FlowState.swift` | 流程状态：钢琴类型、导入曲目与 steps |
| `Models/Calibration/` | KeyboardFrame、PianoCalibration、PianoKeyboardGeometry、StoredWorldAnchorCalibration |
| `Models/Practice/` | PracticeStep、PianoHighlightGuide、DetectedNoteEvent 等 |
| `Models/MIDI/` | MIDI1InputEvent、MIDI2InputEvent（BLE MIDI 输入事件模型） |
| `Models/Recording/` | RecordingTake、RecordingTakeEvent |
| `ViewModels/ARGuide/` | ARGuideViewModel（练习定位、provider 状态、沉浸空间运行时）、CalibrationFlowViewModel、PracticeLocalizationViewModel |
| `ViewModels/WindowCoordinator.swift` | 窗口导航编排（preparation/library/practice 单窗口可见）+ `FlowState` 清理 |
| `ViewModels/PracticeSession/` | PracticeSessionViewModel + extension 文件（Commands / HandInput / HighlightGuides / Orchestration / Playback）+ PracticeSessionStateStore |
| `ViewModels/Library/SongLibraryViewModel.swift` | 曲库导入/删除/试听 |
| `ViewModels/MIDI/MIDISourceConnectionViewModel.swift` | BLE MIDI 连接状态监控 |
| `ViewModels/Recording/TakeLibraryViewModel.swift` | Take 库管理 |
| `Services/AppFlow/` | PianoModeProtocol、PianoModeRegistryService、DefaultPianoModes（三种钢琴模式） |
| `Services/Audio/` | PracticeSequencer playback/sequence builder、PracticeAudioError |
| `Services/AudioRecognition/` | 谐波模板检测（16 文件）：HarmonicTemplateScorer、TargetedHarmonicTemplateDetector、VDSPAudioSpectrumAnalyzer 等 |
| `Services/Bluetooth/` | BluetoothAccessPreflight（BLE 权限预检） |
| `Services/Calibration/` | CalibrationPointCaptureService、CalibrationRepository |
| `Services/HandTracking/` | PressDetectionService、RealPianoContactDetectionService |
| `Services/Library/` | SongFileStore、SongLibraryIndexStore、BundledSongLibraryProvider、AudioImportService 等 |
| `Services/MIDI/` | BluetoothMIDIInputEventSourceService（CoreMIDI UMP → events）、CoreMIDISourceMonitoringService |
| `Services/MusicXML/` | 解析和时间线（Parser/ 子目录 + 13 个 timeline/expander/velocity 文件） |
| `Services/Networking/` | BonjourBackendDiscoveryService、ImprovBackendClient |
| `Services/Placement/` | GazePlaneHitTestService、VirtualKeyboardPoseService |
| `Services/Practice/` | PracticeStepBuilder + 按用途拆分的子目录：AI/（PhraseRecorder、ImprovScheduleBuilder、AIPerformanceCoordinator）、Autoplay/（AutoplayPerformanceTimeline）、Guides/（GrandStaffNotationLayoutService、PianoHighlightGuideBuilderService、PracticeHighlightGuideController）、Input/（PracticeAudioRecognitionCoordinator、PracticeMIDIInputCoordinator、VirtualPianoInputController）、ManualAdvance/、Matching/（AudioStepAttemptAccumulator、ChordAttemptAccumulator、MIDIPracticeStepMatcher、PracticeHandGateController、StepMatcher）、Navigation/（PracticeStepNavigator）、Playback/（PlaybackSequenceBuilder、PracticeManualReplayCoordinator、PracticePlaybackCoordinator）、Session/（PracticeSessionCoordinatorProtocols、PracticeSessionViewModelFactoryService、PracticePreparationService） |
| `Services/Recording/` | MIDIRecordingAdapter、RecordingTakeRecorder、RecordingTakeStore、TakePlaybackController |
| `Services/Tracking/` | ARTrackingService |
| `Services/VirtualPiano/` | KeyContactDetectionService、VirtualPianoKeyGeometryService |
| `Views/PianoChoose/` | PianoTypePickerView、Real/BluetoothMIDI/Virtual 准备页、校准流程 |
| `Views/Preparation/` | PreparationWindowRootView（preparation 窗口 root，模式选择/准备页派发） |
| `Views/Library/` | LibraryWindowRootView、LibraryFlowView、SongLibraryView |
| `Views/Practice/` | PracticeWindowRootView、PracticeFlowView、PracticeStepView、GrandStaffNotationView 等 |
| `Services/Immersive/` | RealityKit overlay controllers（校准、贴皮高亮、虚拟钢琴、沉浸式五线谱、虚拟表演者等）+ XiaochengRig；由 `Views/Shared/ImmersiveView.swift` 统一驱动 update |
| `Views/MIDI/BluetoothMIDICentralView.swift` | 系统 Bluetooth MIDI 配对 UI 包装 |
| `Views/Library/SongLibraryView.swift` | 曲库列表 UI |
| `Views/Practice/` | `GrandStaffNotationView`（双谱表五线谱）、Step3AudioDebugOverlay |
| `Views/Recording/TakeLibraryView.swift` | Take 库 UI |
| `Views/AppFlow/` | PianoModePreparationRoute、PianoModePreparationRouterView、PracticeFlowCoordinator |
| `Services/AppCompositionRoot.swift` | 应用级依赖组装根 |
| `Services/AppServices.swift` | 服务容器 |
| `Services/Concurrency/` | AsyncStreamBroadcaster |
| `Services/Diagnostics/` | MIDIDiagnosticsConfiguration |
| `Services/Time/` | Sleeper |
| `Services/PianoKeyGeometryService.swift` | 琴键几何协议与实现 |

## 入口与生命周期
| 入口 | 行为 |
| --- | --- |
| `LonelyPianistAVPApp.swift` | 创建 `AppCompositionRoot` 与 `WindowCoordinator`，声明 3×`Window`（preparation/library/practice）+ `ImmersiveSpace` 并注入共享依赖 |
| `Views/*WindowRootView.swift` | 各窗口 root 获取 `openWindow/dismissWindow` 环境动作；目标窗口在激活后 `dismissWindow(id: from)` 关闭来源窗口，保证单窗口可见 |
| `ARGuideViewModel.enterPracticeStep()` | 开启练习定位（虚拟钢琴模式跳过实体定位） |
| `ARGuideViewModel.enterVirtualPianoPlacement()` | 虚拟钢琴准备阶段：打开沉浸空间并进入放置引导 |
| `SongLibraryViewModel.preparePractice()` | 解析谱面并写入 `FlowState`（触发 session 注入） |

## Bluetooth MIDI（BLE）
- 入口：`Views/PianoChoose/BluetoothPianoPreparationView.swift`（类型选择后进入该准备页；仅 2D Window）。
- 系统连接 UI：`Views/MIDI/BluetoothMIDICentralView.swift` 包装 `CoreAudioKit.CABTMIDICentralViewController`；准备页使用 `BluetoothMIDICentralEmbeddedView` **内嵌**系统面板（不做 app 私有扫描/连接）。
- 权限预检与引导：`Services/Bluetooth/BluetoothAccessPreflight.swift` + `NSBluetoothAlwaysUsageDescription`（见 `LonelyPianistAVP/Info.plist`）。
- 连接确认抓手：`ViewModels/MIDI/MIDISourceConnectionViewModel.swift`（sources 列表 + sourceCount）+ `Services/MIDI/CoreMIDISourceMonitoringService.swift`。
- Gate（是否允许进入曲库/练习）：由当前 `PianoModeProtocol.canProceedToLibrary(flowState:)` 决定；BLE MIDI 模式要求 `FlowState.bluetoothMIDISourceCount > 0` 且校准完成。
- Step 3 输入源：由 `FlowState.selectedPianoModeID`（模式 id 字符串）经 `PianoModeRegistryService` 解析为具体 `PianoModeProtocol` 决定，进入练习前由 `PracticeSessionViewModelFactoryService` 注入对应 session（BLE 模式为 **MIDI-only**：不启音频识别，且 practice 阶段不启 hand tracking consumer）。
- 练习输入事件模型：`Models/MIDI/MIDI1InputEvent.swift` / `Models/MIDI/MIDI2InputEvent.swift`，BLE 事件源：`Services/MIDI/BluetoothMIDIInputEventSourceService.swift`（CoreMIDI UMP → MIDI1/MIDI2 streams）。
- 练习推进：BLE MIDI 模式用 `MIDIPracticeStepMatcher` 做 deterministic step 判定（不复用音频识别 accumulator）。
- 录制：BLE 模式下 take/phrase 从 MIDI events 录制（`Services/Recording/MIDIRecordingAdapter.swift` + `Services/Recording/RecordingTakeRecorder.swift` + `Services/Practice/AI/PhraseRecorder.swift`）。
- 验收要点：visionOS Simulator 无法可靠验证 BLE MIDI；以 Vision Pro 真机冒烟为准。

### 真机冒烟清单（Vision Pro）
- 准备页：进入 `BluetoothMIDIPreparationView` 后应直接看到系统连接面板；权限被拒绝时应出现“打开设置”引导。
- 连接：在系统面板点 `Connect` 后，准备页应显示 `已连接 Sources: N`（`N > 0`）。
- Gate：完成 Step 1 校准后，「下一步：去选曲」可用，并能进入曲库/练习。
- 练习推进：进入练习后弹奏 1 个 note-on，应能推进 step（无需手势/hand tracking）。
- 录制：点击「开始录制」，弹奏 note-on/off + CC64（踏板）/pitch bend/program change 后结束录制；Take 库能回放（音色可忽略，重点验证事件落盘与回放不崩）。
- AI：开启虚拟表演者后，弹奏一小段 phrase，静默 ~2s 应触发生成/回放（后端不可用时走本地 fallback）。

## Library

曲库页覆盖 seed、导入、删除、音频绑定、试听和索引一致性。

关键对象：
- `SongLibraryViewModel`：曲库编排
- `BundledSongLibraryProvider`：提供 app bundle 内置曲目（运行时合并展示）
- `SongLibraryIndexStore`：索引读写（`index.json` 原子写入）
- `SongFileStore`：曲谱文件复制 / 删除
- `AudioImportService`：音频文件复制

行为要点：
- 内置曲目来自 app bundle（`Resources/SeedScores`），不写入 `index.json`；与用户导入的索引条目合并展示。
- 导入顺序：先复制文件，再提交索引。
- 删除顺序：先删索引，再删文件。

## Calibration

校准页覆盖 A0/C8 捕获、世界锚点存储、恢复、重新校准和定位前置条件。

关键对象：
- `ARGuideViewModel`：Step 3 编排
- `CalibrationFlowViewModel`：Step 1 校准流程编排
- `CalibrationPointCaptureService`：准星稳定判定与 anchor id 记录
- `WorldAnchorCalibrationStore`：JSON 持久化
- `KeyboardFrame`：从 A0/C8 推导键盘局部坐标系（用于渲染与按键检测）

约定要点：
- runtime calibration 会把 A0/C8 解释为琴键“前沿线”（keyboard-local `z = 0`），再结合 `DeviceAnchor` 判定琴键内部方向。

## MusicXML

AVP 从 MusicXML 到“可练习数据结构”的关键管线入口是 `PracticePreparationService.prepare(from:file:)`，核心步骤：
- （可选）结构展开：`MusicXMLStructureExpander`
- 双 part 钢琴谱归一化：`MusicXMLPianoGrandStaffNormalizer`（把高/低音谱号两个 `<part>` 合并为单 part + staff=1/2）
- 单谱表自动分手：`MusicXMLHandRouter`（在缺失 staff 的情况下补 staff=1/2，供左右手语义 + 双谱表渲染 + 按手判定复用）
- step 生成：`PracticeStepBuilder`（输出 `PracticeStep[]`，note 的 hand 由 staff 推导）

相关测试：
- `MusicXMLPianoGrandStaffNormalizerTests`
- `MusicXMLHandRouterTests`

## Tracking

追踪页覆盖 Hand/World/Plane providers、授权、provider 状态、finger tips 分发与 anchors 维护；入口通常是 `ARTrackingService.start(mode:)`。

模式（`ARTrackingMode`）要点：
- `calibration`：Hand + World + Plane（Step 1）
- `practiceVirtualOrAudio`：Hand + World + Plane（虚拟钢琴/音频练习）
- `practiceBluetoothMIDI`：World + Plane（BLE MIDI 练习：不请求 hand tracking 权限）

## Piano modes（能力矩阵）

三模式（真实钢琴音频 / 真实钢琴 BLE MIDI / 虚拟钢琴）由 `PianoModeProtocol` 表达为“体验能力集合”，并由：
- `PianoModeRegistryService` 注册
- `PracticeSessionViewModelFactoryService` 按模式注入 Step 3 会话依赖

## Practice

Step 3 练习细节（匹配、五线谱、贴皮高亮、虚拟钢琴、AI 即兴）集中在 `lonelypianist-avp-practice.md`。

## 风险点
- `resolveRuntimeCalibrationFromTrackedAnchors`
- `runPracticeLocalization`
- `importMusicXML`
- `startAutoplayTaskIfNeeded`


## Coverage Gaps
- AVP 的手部追踪、平面检测、贴皮高亮视觉舒适度与虚拟钢琴放置体验仍需要 Vision Pro 真机验证；simulator 无法覆盖真实传感数据质量。
