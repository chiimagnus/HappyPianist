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
| `Models/Practice/` | PracticeStep、PracticeInputEvent、PianoHighlightGuide、DetectedNoteEvent 等 |
| `Models/Recording/` | RecordingTake、RecordingTakeEvent |
| `ViewModels/ARGuideViewModel.swift` | 练习定位、provider 状态、沉浸空间运行时 |
| `ViewModels/WindowCoordinator.swift` | 窗口导航编排（preparation/library/practice 单窗口可见）+ `FlowState` 清理 |
| `ViewModels/PracticeSession/` | PracticeSessionViewModel 拆分的 6 个 extension（AudioRecognition / Autoplay / HandGate / HighlightGuides / ManualReplay / PracticeInput） |
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
| `Services/Practice/` | PracticeStepBuilder + 按用途拆分的子目录：AI/（PhraseRecorder、ImprovScheduleBuilder）、Autoplay/、Guides/、ManualAdvance/、Matching/、Session/ |
| `Services/Recording/` | MIDIRecordingAdapter、RecordingTakeRecorder、RecordingTakeStore、TakePlaybackController |
| `Services/Tracking/` | ARTrackingService |
| `Services/VirtualPiano/` | KeyContactDetectionService、VirtualPianoKeyGeometryService |
| `Views/PianoChoose/` | PianoTypePickerView、Real/BluetoothMIDI/Virtual 准备页、校准流程 |
| `Views/Preparation/` | PreparationWindowRootView（preparation 窗口 root，模式选择/准备页派发） |
| `Views/Library/` | LibraryWindowRootView、LibraryFlowView、SongLibraryView |
| `Views/Practice/` | PracticeWindowRootView、PracticeFlowView、PracticeStepView、GrandStaffNotationView 等 |
| `Services/Immersive/` | RealityKit overlay controllers（校准、贴皮高亮、虚拟钢琴、沉浸式五线谱等）；由 `Views/Shared/ImmersiveView.swift` 统一驱动 update |
| `Views/MIDI/BluetoothMIDICentralView.swift` | 系统 Bluetooth MIDI 配对 UI 包装 |
| `Views/Library/SongLibraryView.swift` | 曲库列表 UI |
| `Views/Practice/` | `GrandStaffNotationView`（双谱表五线谱）、Step3AudioDebugOverlay |
| `Views/Recording/TakeLibraryView.swift` | Take 库 UI |

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
- 练习输入事件模型：`Models/Practice/PracticeInputEvent.swift`（G1 channel voice），BLE 事件源：`Services/MIDI/BluetoothMIDIInputEventSourceService.swift`（CoreMIDI UMP → events）。
- 录制：BLE 模式下 take/phrase 从 MIDI events 录制（`Services/Recording/MIDIRecordingAdapter.swift` + `Services/Recording/RecordingTakeRecorder.swift` + `Services/Practice/AI/PhraseRecorder.swift`）。
- 验收要点：visionOS Simulator 无法可靠验证 BLE MIDI；以 Vision Pro 真机冒烟为准。

### 真机冒烟清单（Vision Pro）
- 准备页：进入 `BluetoothMIDIPreparationView` 后应直接看到系统连接面板；权限被拒绝时应出现“打开设置”引导。
- 连接：在系统面板点 `Connect` 后，准备页应显示 `已连接 Sources: N`（`N > 0`）。
- Gate：完成 Step 1 校准后，「下一步：去选曲」可用，并能进入曲库/练习。
- 练习推进：进入练习后弹奏 1 个 note-on，应能推进 step（无需手势/hand tracking）。
- 录制：点击「开始录制」，弹奏 note-on/off + CC64（踏板）/pitch bend/program change 后结束录制；Take 库能回放（音色可忽略，重点验证事件落盘与回放不崩）。
- AI：开启虚拟表演者后，弹奏一小段 phrase，静默 ~2s 应触发生成/回放（后端不可用时走本地 fallback）。

## 重要子页
- [Library](lonelypianist-avp-library.md)
- [Calibration](lonelypianist-avp-calibration.md)
- [MusicXML](lonelypianist-avp-musicxml.md)
- [Tracking](lonelypianist-avp-tracking.md)
- [Practice](lonelypianist-avp-practice.md)

## 风险点
- `resolveRuntimeCalibrationFromTrackedAnchors`
- `runPracticeLocalization`
- `importMusicXML`
- `startAutoplayTaskIfNeeded`


## Coverage Gaps
- AVP 的手部追踪、平面检测、贴皮高亮视觉舒适度与虚拟钢琴放置体验仍需要 Vision Pro 真机验证；simulator 无法覆盖真实传感数据质量。
