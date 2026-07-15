# Module: HappyPianistAVP

`HappyPianistAVP/` 是 Apple Vision Pro App target，围绕准备、曲库、练习三个窗口和一个 mixed immersive space 组织。

## App 与窗口

| 代码 | 作用 |
| --- | --- |
| `HappyPianistAVP/Views/HappyPianistAVPApp.swift` | 创建 `AppState`，声明三个窗口与 `ImmersiveSpace`。 |
| `HappyPianistAVP/Models/WindowID.swift` | `preparation`、`library`、`practice` window ID。 |
| `HappyPianistAVP/ViewModels/LiveAppGraph.swift` | live composition root 与共享依赖。 |
| `HappyPianistAVP/ViewModels/PracticeSetupState.swift` | 准备阶段 readiness 状态。 |
| `HappyPianistAVP/ViewModels/WindowTransitionState.swift` | 窗口替换 transition。 |
| `HappyPianistAVP/ViewModels/ARGuide/ARGuideViewModel.swift` | 练习、追踪、沉浸空间、录制与 AI 的总协调器。 |
| `HappyPianistAVP/ViewModels/PracticeLaunch/PracticeLaunchViewModel.swift` | 唯一的练习启动 request、激活、失败、scene suspend 与 prepared-song 清理 owner。 |

窗口使用系统背景；切换时由 `WindowTransitionState` 记录事务，目标根视图显式关闭来源窗口。曲库主窗口保留唱片浏览、曲名/作曲家、试听控件和唯一“开始练习”按钮，trailing Ornament 只读展示当前曲目的练习事实。

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
| `HappyPianistAVP/ViewModels/Library/SongLibraryViewModel.swift` | 接收异步 bootstrap snapshot，合并 bundled/imported entries，并作为唯一 selection owner 管理试听、导入和删除；selection 持久化与练习事实 snapshot 各有独立 generation。 |
| `HappyPianistAVP/Services/Library/SongPracticeLibrarySnapshotBuilder.swift` | 从单曲 history 纯派生当前版本/真实 attempt facts，不读取文件或 UI 类型。 |
| `HappyPianistAVP/Views/Library/LibraryPracticeProgressOrnamentView.swift` | 以原生 trailing Ornament 和单一内部 `ScrollView` 只读展示 loading、首次练习邀请、当前概览、重建提示与 unavailable；外层完全使用 visionOS `glassBackgroundEffect`，内部卡片与前景统一使用系统 Material、系统 tint 和语义层级，不定义 Ornament 专用调色板；钢琴、琴键按压与音符漂浮均由 SwiftUI Shape、SF Symbols 和 `phaseAnimator` 原生实现，并支持 Reduce Motion，无配置控件或练习按钮。 |
| `HappyPianistAVP/Services/Library/SongLibraryBootstrapLoader.swift` | actor 隔离的首次 bundle 扫描与索引解码，避免阻塞 MainActor 启动。 |
| `HappyPianistAVP/Services/Library/SongLibraryImportTransactionService.swift` | 原名 batch staging、确认时事实重分类、indexed replace / missing repair / orphan adopt、取消与 bootstrap recovery 的唯一 owner。 |
| `HappyPianistAVP/Services/Library/SongFileStore.swift` | 解析及删除已经入库的用户 score/audio 文件；不执行曲谱导入。 |
| `HappyPianistAVP/Services/Library/SongLibraryIndexStore.swift` | actor 内按 concern 原子更新用户曲库索引。 |
| `HappyPianistAVP/Services/Library/BundledSongLibraryProvider.swift` | 扫描 App bundle 中的 `.musicxml`。 |
| `HappyPianistAVP/Services/Library/AudioImportService.swift` | 绑定 `.mp3` / `.m4a` 试听音频。 |
| `HappyPianistAVP/Services/Practice/Session/PracticePreparationService.swift` | 把所选曲谱转换成 `PreparedPractice`。 |

支持 `.musicxml`、`.xml`、`.mxl`。切换唱片只更新 selection 并异步读取同曲 history JSON；点击主内容中唯一的“开始练习”才登记 request 并打开练习窗口，曲谱解析、进度恢复和失败展示都由练习窗口拥有。snapshot generation 同时绑定 song UUID 与 entry token，旧结果不能覆盖新选择，且 Library/Ornament 不访问 score/preparation/session。Ornament 没有隐藏配置或练习入口。

正式生产导入链只有：

```text
Library View -> SongLibraryViewModel -> SongLibraryImportTransactionService -> SongLibraryIndexStore
```

同名确认只携带 operation ID。现有 target 的替换与 orphan adopt 使用 destructive action；缺失 target 修复使用非 destructive action；多个 entry 指向同一 target 时不显示覆盖动作。entry CAS 保留非曲谱字段，新的 version token 让旧练习事实保留为历史但不会当成当前版本恢复。

不要重新引入平行的 MusicXML import service。

源码归档没有 bundled production score；`BundledSongLibraryProvider` 只有在 App target 实际包含 `.musicxml` 时才会产生内置曲目。


## 诊断

曲库顶部“诊断”入口打开全局诊断管理界面，可查看日志覆盖范围、清除日志并导出7 天的诊断 ZIP。业务代码只写 `DiagnosticEvent`；`AppDiagnosticsReporter` 同时负责 `os.Logger` 与受隐私规则约束的 JSONL 存储。

曲谱准备失败在练习窗口中显示具体标题、解释、错误代码、阶段、文件名、App 内相对路径和可用的行列。技术详情可通过系统文本选择菜单复制。

## 练习窗口

`HappyPianistAVP/Views/Practice/PracticeWindowRootView.swift` 承载：

- launch loading / failure / retry 与唯一返回事务
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
