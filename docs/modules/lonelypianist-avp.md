# Module: LonelyPianistAVP

`LonelyPianistAVP/` 是 Apple Vision Pro 练习端。它围绕“准备 -> 曲库 -> 练习”三窗口和一个沉浸空间组织代码。

## App 与窗口

| 代码 | 说明 |
| --- | --- |
| `LonelyPianistAVP/Views/LonelyPianistAVPApp.swift` | `@main` app，创建 `AppState`，声明 preparation/library/practice windows 与 `ImmersiveSpace`。 |
| `LonelyPianistAVP/Models/WindowID.swift` | 窗口 id：`preparation`、`library`、`practice`。 |
| `LonelyPianistAVP/ViewModels/AppState.swift` | 依赖图、校准、曲库、AR guide、piano mode registry 与 window state。 |
| `LonelyPianistAVP/ViewModels/PracticeSetupState.swift` | 准备阶段状态。 |
| `LonelyPianistAVP/ViewModels/WindowTransitionState.swift` | 跨窗口 transition 状态。 |

当前代码没有 `LonelyPianistAVP/Models/AppFlow/FlowState.swift`、`LonelyPianistAVP/ViewModels/WindowCoordinator.swift` 或 `LonelyPianistAVP/Services/AppFlow/`。

## 钢琴模式

| 模式 | 类型 | 进入曲库条件 | 练习追踪模式 |
| --- | --- | --- | --- |
| 真实钢琴（音频） | `RealAudioPianoMode` | A0/C8 校准完成 | `.practiceVirtualOrAudio` |
| 真实钢琴（蓝牙 MIDI） | `BluetoothMIDIPianoMode` | A0/C8 校准完成且 source 数量大于 0 | `.practiceBluetoothMIDI`，若启用虚拟琴则转为 `.practiceVirtualOrAudio` |
| 虚拟钢琴 | `VirtualPianoMode` | 虚拟钢琴完成放置 | `.practiceVirtualOrAudio` |

模式注册由 `PianoModeCatalogService.makeDefaultModes()` 与 `PianoModeRegistryService` 完成。

## 准备阶段 UI

| 代码 | 说明 |
| --- | --- |
| `LonelyPianistAVP/Views/PianoChoose/Preparation/PreparationWindowRootView.swift` | preparation window root。 |
| `LonelyPianistAVP/Views/PianoChoose/PianoTypePickerView.swift` | 选择钢琴类型。 |
| `LonelyPianistAVP/Views/PianoChoose/PianoModePreparationRouterView.swift` | 根据 mode route 到准备页。 |
| `LonelyPianistAVP/Views/PianoChoose/MicrophonePianoPreparationView.swift` | 真实钢琴音频准备。 |
| `LonelyPianistAVP/Views/PianoChoose/BluetoothPianoPreparationView.swift` | BLE MIDI 准备，嵌入 `CABTMIDICentralViewController`。 |
| `LonelyPianistAVP/Views/PianoChoose/VirtualPianoPreparationView.swift` | 虚拟琴放置准备。 |

## 曲库

| 代码 | 说明 |
| --- | --- |
| `LonelyPianistAVP/ViewModels/Library/SongLibraryViewModel.swift` | 合并 bundled entries 与用户导入 entries，管理导入、删除、音频绑定与进入练习。 |
| `LonelyPianistAVP/Services/Library/BundledSongLibraryProvider.swift` | 扫描 bundle 内置曲谱。 |
| `LonelyPianistAVP/Services/Library/SongFileStore.swift` | 写入用户导入 MusicXML。 |
| `LonelyPianistAVP/Services/Library/AudioImportService.swift` | 写入用户绑定音频。 |
| `LonelyPianistAVP/Services/Practice/Session/PracticePreparationService.swift` | 把 MusicXML 转成 `PreparedPractice`。 |

## 沉浸空间

| 代码 | 说明 |
| --- | --- |
| `LonelyPianistAVP/Views/Shared/ImmersiveView.swift` | RealityKit/ARKit overlay 容器。 |
| `LonelyPianistAVP/Services/Tracking/ARTrackingService.swift` | 根据 `ARTrackingMode` 启停 hand/world/plane providers。 |
| `LonelyPianistAVP/Services/Immersive/*OverlayController.swift` | 校准、琴键高亮、虚拟琴、虚拟演奏者等 overlay。 |
| `LonelyPianistAVP/ViewModels/ARGuide/ARGuideViewModel.swift` | 沉浸空间总协调器。 |

ARKit provider 只应在沉浸空间内运行；窗口 UI 不应假设 hand/world/plane data 在 shared space 可用。

## 本地验证

```bash
rtk xcodebuild -showdestinations -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP
rtk xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,id=<device-id>' CODE_SIGNING_ALLOWED=NO
```

真机才可验证 hand tracking、plane detection、Bluetooth MIDI、Local Network/Bonjour、Microphone 与空间舒适度。
