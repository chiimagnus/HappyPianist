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

窗口使用系统背景与 replacement placement。曲库主窗口保留唱片浏览、曲名/作曲家与试听控件；练习信息与设置使用附着在 scene trailing 的 Ornament，不把主窗口改成内部 split view。

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
| `HappyPianistAVP/ViewModels/Library/SongLibraryViewModel.swift` | 接收异步 bootstrap snapshot，合并 bundled/imported entries，管理选择、试听、导入、删除和进入练习。 |
| `HappyPianistAVP/Services/Library/SongLibraryBootstrapLoader.swift` | actor 隔离的首次 bundle 扫描与索引解码，避免阻塞 MainActor 启动。 |
| `HappyPianistAVP/Services/Library/SongFileStore.swift` | 导入 MusicXML 到 Documents。 |
| `HappyPianistAVP/Services/Library/SongLibraryIndexStore.swift` | 保存用户曲库索引。 |
| `HappyPianistAVP/Services/Library/BundledSongLibraryProvider.swift` | 扫描 App bundle 中的 `.musicxml`。 |
| `HappyPianistAVP/Services/Library/AudioImportService.swift` | 绑定 `.mp3` / `.m4a` 试听音频。 |
| `HappyPianistAVP/Services/Practice/Session/PracticePreparationService.swift` | 把所选曲谱转换成 `PreparedPractice`。 |

支持 `.musicxml`、`.xml`、`.mxl`。切换唱片后自动异步准备当前曲谱；右侧 Ornament 固定呈现骨架、练习信息/设置或具体失败原因。底部固定按钮统一为“去练习！”，直接使用当前 pending configuration，不再弹出练习选择 dialog 或 sheet。

曲名、作曲家、来源与试听播放仍属于主曲库内容；练习范围、手别、速度、循环、连续成功目标、恢复点、卡点和小节地图只属于右侧 Ornament。

正式生产导入链只有：

```text
Library View -> SongLibraryViewModel -> SongFileStore
```

不要重新引入平行的 MusicXML import service。

源码归档没有 bundled production score；`BundledSongLibraryProvider` 只有在 App target 实际包含 `.musicxml` 时才会产生内置曲目。


## 诊断

曲库顶部“诊断”入口打开全局诊断管理界面，可查看日志覆盖范围、清除日志并导出7 天的诊断 ZIP。业务代码只写 `DiagnosticEvent`；`AppDiagnosticsReporter` 同时负责 `os.Logger` 与受隐私规则约束的 JSONL 存储。

曲谱准备失败在右侧 Ornament 中显示具体标题、解释、错误代码、阶段、文件名、App 内相对路径和可用的行列/小节。技术详情默认可见并通过系统文本选择菜单复制。

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
| `HappyPianistAVP/Services/Tracking/ARTrackingService.swift` | 按 `ARTrackingRequirements` 管理最小 ARKit provider 集合，并发布 newest-only typed 手部快照。 |
| `HappyPianistAVP/Models/Tracking/FingerTipsSnapshot.swift` | 固定手别与手指身份的 typed snapshot，替代逐帧字符串字典。 |
| `HappyPianistAVP/Services/HandTracking/PianoKeyHitTestIndex.swift` | 键盘几何索引与常数级相邻候选命中。 |
| `Services/Immersive/*OverlayController.swift` | 校准、琴键、虚拟钢琴和调试 overlay。 |
| `PianoGuideOverlayController` | 高亮与练习恢复效果的共享 root。 |

规则：

- ARKit provider 只在 immersive space 内运行；平面检测仅在虚拟琴尚未完成摆放时启用。
- 虚拟琴引导只有一个 30 Hz 驱动循环；手部 stream 只更新最新快照，不直接触发第二次 guidance。
- 进入后台、换曲、restart、关闭窗口和退出 immersive 时清理 tracking session、订阅、长生命周期 task 与 entity。
- 钢琴键 mesh/material 由沉浸视图持有的共享工厂复用。
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
