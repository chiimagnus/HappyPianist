# Module: HappyPianistAVP

`HappyPianistAVP/` 是 Apple Vision Pro 练习端。它围绕“准备 -> 曲库 -> 练习”三窗口和一个沉浸空间组织代码。

## App 与窗口

| 代码 | 说明 |
| --- | --- |
| `HappyPianistAVP/Views/HappyPianistAVPApp.swift` | `@main` app，创建 `AppState`，声明 preparation/library/practice windows 与 `ImmersiveSpace`。 |
| `HappyPianistAVP/Models/WindowID.swift` | 窗口 id：`preparation`、`library`、`practice`。 |
| `HappyPianistAVP/ViewModels/AppState.swift` | 依赖图、校准、曲库、AR guide、piano mode registry 与 window state。 |
| `HappyPianistAVP/ViewModels/PracticeSetupState.swift` | 准备阶段状态。 |
| `HappyPianistAVP/ViewModels/WindowTransitionState.swift` | 跨窗口 transition 状态。 |

当前代码没有 `HappyPianistAVP/Models/AppFlow/FlowState.swift`、`HappyPianistAVP/ViewModels/WindowCoordinator.swift` 或 `HappyPianistAVP/Services/AppFlow/`。

## 钢琴模式

| 模式 | 类型 | 进入曲库条件 | 练习追踪模式 |
| --- | --- | --- | --- |
| 真实钢琴（音频） | `RealAudioPianoMode` | A0/C8 校准完成 | `.practiceVirtualOrAudio` |
| 真实钢琴（蓝牙 MIDI） | `BluetoothMIDIPianoMode` | A0/C8 校准完成且 source 数量大于 0 | `.practiceBluetoothMIDI`，若启用虚拟琴则转为 `.practiceVirtualOrAudio` |
| 虚拟钢琴 | `VirtualPianoMode` | 虚拟钢琴完成放置 | `.practiceVirtualOrAudio` |

模式注册由 `PianoModeCatalogService.makeDefaultModes()` 与 `PianoModeRegistryService` 完成。

### 蓝牙 MIDI 模式的发声路由

当选择“真实钢琴（蓝牙 MIDI）”时，练习回放支持两种路由：

- 仅 AVP 发声：使用 AVP 内置 sampler（音量由练习设置里的“输出音量（AVP）”控制）。
- 仅真实钢琴发声：把回放事件通过 CoreMIDI 发送到用户选择的 MIDI destination（`kMIDIPropertyUniqueID` 可能为负数；`0` 表示未选择）。

## 准备阶段 UI

| 代码 | 说明 |
| --- | --- |
| `HappyPianistAVP/Views/PianoChoose/Preparation/PreparationWindowRootView.swift` | preparation window root。 |
| `HappyPianistAVP/Views/PianoChoose/PianoTypePickerView.swift` | 选择钢琴类型。 |
| `HappyPianistAVP/Views/PianoChoose/PianoModePreparationRouterView.swift` | 根据 mode route 到准备页。 |
| `HappyPianistAVP/Views/PianoChoose/MicrophonePianoPreparationView.swift` | 真实钢琴音频准备。 |
| `HappyPianistAVP/Views/PianoChoose/BluetoothPianoPreparationView.swift` | BLE MIDI 准备，嵌入 `CABTMIDICentralViewController`。 |
| `HappyPianistAVP/Views/PianoChoose/VirtualPianoPreparationView.swift` | 虚拟琴放置准备。 |

## 曲库

| 代码 | 说明 |
| --- | --- |
| `HappyPianistAVP/ViewModels/Library/SongLibraryViewModel.swift` | 合并 bundled entries 与用户导入 entries，管理导入、删除、音频绑定与进入练习。 |
| `HappyPianistAVP/Services/Library/BundledSongLibraryProvider.swift` | 扫描 bundle 内置曲谱。 |
| `HappyPianistAVP/Services/Library/SongFileStore.swift` | 写入用户导入 MusicXML。 |
| `HappyPianistAVP/Services/Library/AudioImportService.swift` | 写入用户绑定音频。 |
| `HappyPianistAVP/Services/Practice/Session/PracticePreparationService.swift` | 把 MusicXML 转成 `PreparedPractice`。 |

曲库 UI 直接使用 visionOS 系统窗口背景，并通过 `ToolbarItemGroup(placement: .bottomOrnament)` 提供播放与开始练习操作。中心唱片上拽可导入 `.xml`、`.musicxml` 或 `.mxl`；用户曲目的音频替换与删除位于唱片 context menu。

## 沉浸空间

| 代码 | 说明 |
| --- | --- |
| `HappyPianistAVP/Views/Shared/ImmersiveView.swift` | RealityKit/ARKit overlay 容器。 |
| `HappyPianistAVP/Services/Tracking/ARTrackingService.swift` | 根据 `ARTrackingMode` 启停 hand/world/plane providers。 |
| `HappyPianistAVP/Services/Immersive/*OverlayController.swift` | 校准、琴键高亮、虚拟琴、虚拟演奏者等 overlay。 |
| `HappyPianistAVP/ViewModels/ARGuide/ARGuideViewModel.swift` | 沉浸空间总协调器。 |

ARKit provider 只应在沉浸空间内运行；窗口 UI 不应假设 hand/world/plane data 在 shared space 可用。

## 本地验证

```bash
xcodebuild -showdestinations -project HappyPianist.xcodeproj -scheme HappyPianistAVP
xcodebuild test -project HappyPianist.xcodeproj -scheme HappyPianistAVP -destination 'platform=visionOS Simulator,id=<device-id>' CODE_SIGNING_ALLOWED=NO
```

真机才可验证 hand tracking、plane detection、Bluetooth MIDI、Microphone 与空间舒适度。

## 可选：网络即兴后端（Aria v2）

AVP 的 AI 即兴默认使用本地后端（CoreML / 本地规则）。当用户在练习设置中选择网络后端时，AVP 会：

- 通过 Bonjour 发现 `_lpduet._tcp` 服务（需要真机允许 Local Network 权限）
- 调用 Mac 侧 `python_backend/aria_server/`（HTTP `/generate` 或 WebSocket `/stream`）
