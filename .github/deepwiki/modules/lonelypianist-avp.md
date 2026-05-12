# 模块：LonelyPianistAVP

## 边界
- 负责：Step 1 校准、Step 2 曲库、Step 3 练习、沉浸空间和手部追踪。
- 不负责：macOS MIDI 映射和 Python 推理。

## 目录地图
| 路径 | 角色 |
| --- | --- |
| `AppState.swift` | tracking/runtime calibration/沉浸空间状态枢纽 |
| `Models/AppFlow/FlowState.swift` | 流程状态：钢琴类型、导入曲目与 steps |
| `ViewModels/` | 业务编排 |
| `Models/Placement/` | 平面命中与放置数据结构（ray / plane / hit） |
| `Services/Placement/` | 虚拟钢琴放置相关服务（视线平面命中、键盘姿态推导） |
| `Services/Library/` | 曲库：用户导入索引 + app bundle 内置曲目提供 |
| `Services/MusicXML/` | 解析和时间线 |
| `Services/Tracking/` | AR tracking |
| `Services/Calibration/` | 校准捕获 |
| `Services/VirtualPiano/` | 虚拟钢琴几何与接触检测 |
| `Views/` | Step 1/2/3 UI |
| `Views/Immersive/VirtualPianoOverlayController.swift` | 虚拟钢琴 3D 渲染 |
| `Views/Immersive/GazePlaneDiskOverlayController.swift` | 虚拟钢琴放置引导：绿色圆盘 + 3D 文案 |

## 入口与生命周期
| 入口 | 行为 |
| --- | --- |
| `LonelyPianistAVPApp.swift` | 创建 `AppCompositionRoot`，注入 `AppRouter`，启动 WindowGroup + ImmersiveSpace |
| `Views/AppRootView.swift` | 按 `AppRouter.route` 做 root 切换（类型选择 → 准备 → 曲库 → 练习） |
| `ARGuideViewModel.enterPracticeStep()` | 开启练习定位（虚拟钢琴模式跳过实体定位） |
| `ARGuideViewModel.enterVirtualPianoPlacement()` | 虚拟钢琴准备阶段：打开沉浸空间并进入放置引导 |
| `SongLibraryViewModel.preparePractice()` | 解析谱面并写入 `FlowState`（触发 session 注入） |

## Bluetooth MIDI（BLE）
- 入口：`Views/AppFlow/BluetoothMIDIPreparationView.swift`（类型选择后进入该准备页；仅 2D Window）。
- 系统连接 UI：`Views/MIDI/BluetoothMIDICentralView.swift` 包装 `CoreAudioKit.CABTMIDICentralViewController`（不做 app 私有扫描/连接）。
- 权限预检与引导：`Services/Bluetooth/BluetoothAccessPreflight.swift` + `NSBluetoothAlwaysUsageDescription`（见 `LonelyPianistAVP/Info.plist`）。
- 连接确认抓手：`ViewModels/MIDI/MIDISourceConnectionViewModel.swift`（sources 列表 + sourceCount）+ `Services/MIDI/CoreMIDISourceMonitoringService.swift`。
- Gate（是否允许进入曲库/练习）：`FlowState.bluetoothMIDISourceCount > 0` 且校准完成（见 `AppRouter.canProceedToLibrary`）。
- Step 3 输入源：不再通过设置页切换；而是由 `FlowState.pianoKind`（`.realBluetoothMIDI`）决定，进入练习前由 `PracticeSessionViewModelFactoryService` 注入 **MIDI-only** session（不启音频识别，且 practice 阶段不启 hand tracking consumer）。
- 练习输入事件模型：`Models/Practice/PracticeInputEvent.swift`（G1 channel voice），BLE 事件源：`Services/MIDI/BluetoothMIDIInputEventSourceService.swift`（CoreMIDI UMP → events）。
- 录制：BLE 模式下 take/phrase 从 MIDI events 录制（`Services/Recording/MIDIRecordingAdapter.swift` + `Services/Recording/RecordingTakeRecorder.swift` + `Services/Practice/PhraseRecorder.swift`）。
- 验收要点：visionOS Simulator 无法可靠验证 BLE MIDI；以 Vision Pro 真机冒烟为准。

### 真机冒烟清单（Vision Pro）
- 准备页：进入 `BluetoothMIDIPreparationView` 后会自动弹出系统面板；权限被拒绝时应出现“打开设置”引导。
- 连接：在系统面板点 `Connect`，回到准备页点击「刷新 Sources」，`sourceCount > 0` 且能看到 source 名称列表。
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

## 更新记录（Update Notes）
- 2026-04-26: 修复模块页内部链接；更新 AVP 验证链路描述（shared scheme 已存在且在 CI 使用）。
- 2026-05-01: Step 3 练习的 RealityKit 引导从光柱迁移为琴键贴皮高亮（decal）。
- 2026-05-02: 虚拟钢琴放置改为“视野中心平面 + 双手确认”，新增 placement 模型与服务，并增加圆盘 overlay。
- 2026-05-10: 主流程重构：以 `AppRouter.route` 做 root 切换，引入 `FlowState` 聚合“钢琴类型 + 曲目/steps”，练习页返回回到曲库；移除“练习页虚拟钢琴开关”的产品入口。
- 2026-05-12: 新增 AVP app 内系统 `Bluetooth MIDI…` 入口、权限预检与 sources gate；并将 BLE 模式确立为独立钢琴模式（MIDI-only 输入、practice 阶段不启 hand tracking，take/phrase 从 MIDI 录制）。
