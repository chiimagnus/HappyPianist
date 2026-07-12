# Module: HappyPianistAVP

`HappyPianistAVP/` 是 Apple Vision Pro App target，围绕准备、曲库、练习三个窗口和一个 mixed immersive space 组织。

## App 与窗口

| 代码 | 作用 |
| --- | --- |
| `HappyPianistAVP/Views/HappyPianistAVPApp.swift` | 创建 `AppState`，声明三个窗口与 `ImmersiveSpace`。 |
| `HappyPianistAVP/Models/WindowID.swift` | `preparation`、`library`、`practice` window ID。 |
| `HappyPianistAVP/ViewModels/AppState.swift` | live composition root 与共享依赖。 |
| `HappyPianistAVP/ViewModels/PracticeSetupState.swift` | 准备阶段 readiness 状态。 |
| `HappyPianistAVP/ViewModels/WindowTransitionState.swift` | 窗口替换 transition。 |
| `HappyPianistAVP/ViewModels/ARGuide/ARGuideViewModel.swift` | 练习、追踪、沉浸空间、录制与 AI 的总协调器。 |

窗口使用系统背景与 replacement placement。属于窗口 chrome 的操作优先放在 toolbar/ornament，不在 content 内复制悬浮控制条。

## 钢琴模式

`PianoModeCatalogService.makeDefaultModes()` 注册三种模式：

| 模式 | 进入曲库条件 | 练习输入 |
| --- | --- | --- |
| 真实钢琴（音频） | A0/C8 校准完成 | 麦克风识别 + 手部追踪。 |
| 真实钢琴（蓝牙 MIDI） | 校准完成且至少一个 MIDI source | CoreMIDI MIDI 1.0/2.0。 |
| 虚拟钢琴 | 虚拟键盘放置完成 | 手部接触虚拟琴键。 |

准备 UI 位于 `HappyPianistAVP/Views/PianoChoose/`。模式差异通过 `PianoModeProtocol` 表达，不在 View 中维护平行的 mode switch。

## 曲库

| 代码 | 作用 |
| --- | --- |
| `HappyPianistAVP/ViewModels/Library/SongLibraryViewModel.swift` | 合并 bundled/imported entries，管理选择、试听、导入、删除和进入练习。 |
| `HappyPianistAVP/Services/Library/SongFileStore.swift` | 导入 MusicXML 到 Documents。 |
| `HappyPianistAVP/Services/Library/SongLibraryIndexStore.swift` | 保存用户曲库索引。 |
| `HappyPianistAVP/Services/Library/BundledSongLibraryProvider.swift` | 扫描 App bundle 中的 `.musicxml`。 |
| `HappyPianistAVP/Services/Library/AudioImportService.swift` | 绑定 `.mp3` / `.m4a` 试听音频。 |
| `HappyPianistAVP/Services/Practice/Session/PracticePreparationService.swift` | 把所选曲谱转换成 `PreparedPractice`。 |

支持 `.musicxml`、`.xml`、`.mxl`。正式生产导入链只有：

```text
Library View -> SongLibraryViewModel -> SongFileStore
```

不要重新引入平行的 MusicXML import service。

源码归档没有 bundled production score；`BundledSongLibraryProvider` 只有在 App target 实际包含 `.musicxml` 时才会产生内置曲目。

## 练习窗口

`HappyPianistAVP/Views/Practice/PracticeWindowRootView.swift` 承载：

- 五线谱和 step 控制
- 片段设置
- 练习设置
- 非模态 feedback cue
- round summary
- measure restoration map
- take library

业务状态由 `PracticeSessionViewModel`、反馈 view models 和 `ARGuideViewModel` 提供。View 不直接读写 repository 或设备服务。

详见 [happypianist-avp-practice.md](happypianist-avp-practice.md)。

## 沉浸空间

| 代码 | 作用 |
| --- | --- |
| `HappyPianistAVP/Views/Shared/ImmersiveView.swift` | `RealityView` 容器和 overlay 挂载点。 |
| `HappyPianistAVP/Services/Tracking/ARTrackingService.swift` | 按 `ARTrackingMode` 管理 ARKit providers。 |
| `Services/Immersive/*OverlayController.swift` | 校准、琴键、虚拟钢琴和调试 overlay。 |
| `PianoGuideOverlayController` | 高亮与练习恢复效果的共享 root。 |

规则：

- ARKit provider 只在 immersive space 内运行。
- 进入后台、换曲、restart、关闭窗口和退出 immersive 时清理长生命周期 task 与 entity。
- Reduce Motion 和 Differentiate Without Color 必须有等价表现。

## 录制

练习中的 note/control 事件可写入 `RecordingTakeStore`，在 take library 中回放，并通过 `RecordingMIDIExportService` 导出 MIDI。录制数据属于 AVP App，不依赖已删除或不存在的 macOS target。

## AI 对弹

`ImprovBackendRegistry` 提供：

- 本地规则后端
- 本地 CoreML 后端
- Aria v2 HTTP 后端
- Aria v2 WebSocket streaming 后端

本地 CoreML 需要模型资源；网络后端需要 Mac 侧 Python 服务。系统严格使用用户选择的后端，不做静默 fallback。

## 本地验证

```bash
xcodebuild -showdestinations \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP

xcodebuild test \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP \
  -destination 'platform=visionOS Simulator,id=<device-id>' \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO
```

手部追踪、平面检测、麦克风、Bluetooth MIDI、Local Network、空间对齐与舒适度需要真机。
