# HappyPianistAVP 模块

`HappyPianistAVP/` 是 Apple Vision Pro App target，围绕 Library 主窗口、两个由 Library 单层 push 的钢琴准备 / Practice 窗口和一个 mixed immersive space 组织。

## App 与窗口

| 代码 | 作用 |
| --- | --- |
| `HappyPianistAVP/Views/HappyPianistAVPApp.swift` | 创建 `AppState`，声明三个窗口与 `ImmersiveSpace`。 |
| `HappyPianistAVP/Models/WindowID.swift` | `preparation`、`library`、`practice` window ID。 |
| `HappyPianistAVP/ViewModels/LiveAppGraph.swift` | live composition root 与共享依赖。 |
| `HappyPianistAVP/ViewModels/PracticeSetupState.swift` | 准备阶段 readiness 状态。 |
| `HappyPianistAVP/ViewModels/PianoSetupCoordinator.swift` | 钢琴模式 registry、readiness 状态与重新设置入口。 |
| `HappyPianistAVP/ViewModels/ARGuide/ARGuideViewModel.swift` | 练习、追踪、沉浸空间、录制与 AI 的总协调器。 |
| `HappyPianistAVP/ViewModels/PracticeLaunch/PracticeLaunchViewModel.swift` | 唯一的练习启动 request、激活、失败、scene suspend 与 prepared-song 清理 owner。 |

窗口使用系统背景；App 启动直接进入 Library。曲库左上角按钮通过 `pushWindow` 打开钢琴准备窗口，“开始练习”通过 `pushWindow` 打开 Practice；两个 pushed window 关闭后都恢复原 Library，不维护额外窗口 transition 状态。曲库主窗口保留唱片浏览、曲名/作曲家、试听控件和唯一“开始练习”按钮，trailing Ornament 只读展示当前曲目的练习事实。

## 钢琴模式

`PianoModeCatalogService.makeDefaultModes()` 注册三种模式：

| 模式 | 进入曲库条件 | 练习输入 |
| --- | --- | --- |
| 真实钢琴（音频） | A0/C8 校准完成 | 麦克风识别 + 手部追踪。 |
| 真实钢琴（蓝牙 MIDI） | 校准完成且至少一个 MIDI source | CoreMIDI MIDI 1.0/2.0。 |
| 虚拟钢琴 | 虚拟键盘放置完成 | 手部接触虚拟琴键。 |

准备 UI 位于 `HappyPianistAVP/Views/PianoChoose/`，由曲库左上角入口以单层 `pushWindow` 打开。当前目录按模式拆分：

| 目录 | 责任 |
| --- | --- |
| `PreparationWindowRootView.swift` | 准备窗口根视图与模式路由。 |
| `Bluetooth/` | 蓝牙 MIDI 准备与连接区。 |
| `RealPiano/` | 真实钢琴音频模式与触键校准视图。 |
| `VirtualPiano/` | 虚拟钢琴放置与准备视图。 |

模式差异通过 `PianoModeProtocol` 表达，不在 View 中维护平行的 mode switch。未完成 readiness 时曲库仍可浏览和导入，但不能进入 Practice。

## 曲库

| 代码 | 作用 |
| --- | --- |
| `HappyPianistAVP/ViewModels/Library/SongLibraryViewModel.swift` | 接收异步 bootstrap snapshot，合并 bundled/imported entries，并作为唯一 selection owner 管理试听、导入和删除；selection 持久化与练习事实 snapshot 各有独立 generation。 |
| `HappyPianistAVP/Services/Library/SongPracticeLibrarySnapshotBuilder.swift` | 从单曲 history 在非 MainActor 纯派生四态最终 presentation、跨 revision session summary 与当前 revision facts；不读取 score 文件。 |
| `HappyPianistAVP/Views/Library/LibraryPracticeProgressOrnamentView.swift` | 以原生 trailing Ornament、单一 `ScrollView` 和一次外层 `glassBackgroundEffect` 直接展示 loading、invitation、overview、unavailable；summary/legend 用 `ViewThatFits` 按真实宽度退化，retry/reset 调用真实 intent。内部只使用系统 Material、语义色与 SF Symbols；稳定绿、学习中橙、未练习 secondary 均同时带文字、数量和符号，无 Ornament 专属 RGB 调色板。琴键与无圆形遮罩的音符由 SwiftUI 原生实现，支持 Reduce Motion、VoiceOver、Differentiate Without Color 和增强对比度，无配置控件或练习按钮。 |
| `HappyPianistAVP/Services/Library/SongLibraryBootstrapLoader.swift` | actor 隔离的首次 bundle 扫描与索引解码，避免阻塞 MainActor 启动。 |
| `HappyPianistAVP/Services/Library/SongLibraryImportTransactionService.swift` | 原名 batch staging、确认时事实重分类、indexed replace / missing repair / orphan adopt、取消与 bootstrap recovery 的唯一 owner。 |
| `HappyPianistAVP/Services/Library/SongFileStore.swift` | 解析及删除已经入库的用户 score/audio 文件；不执行曲谱导入。 |
| `HappyPianistAVP/Services/Library/SongLibraryIndexStore.swift` | actor 内按 concern 原子更新用户曲库索引。 |
| `HappyPianistAVP/Services/Library/BundledSongLibraryProvider.swift` | 扫描 App bundle 中的 `.musicxml`。 |
| `HappyPianistAVP/Services/Library/AudioImportService.swift` | 绑定 `.mp3` / `.m4a` 试听音频。 |
| `HappyPianistAVP/Services/Practice/Preparation/PracticePreparationService.swift` | 把所选曲谱转换成 `PreparedPractice`。 |

支持 `.musicxml`、`.xml`、`.mxl`。切换唱片只更新 selection 并异步读取同曲 history JSON；点击主内容中唯一的“开始练习”才登记 request 并 push 练习窗口，曲谱解析、进度恢复和失败展示都由练习窗口拥有。presentation generation 同时绑定 song UUID 与 entry token，旧结果不能覆盖新选择；Library/Ornament 不访问 score URL、preparation 服务或 Practice session controller。Ornament 没有隐藏配置或练习入口。

`PracticePreparationService` 先生成唯一 `ScorePerformancePlan`，再投影 `PracticeStep`、`PianoHighlightGuide`，并结合 source score 生成 `ScoreNotationProjection`。sampler、CoreMIDI、autoplay 和手动重播只消费 plan 事件；`PreparedPractice` 不再保存平行 tempo、pedal、fermata 或 note-span 声音事实。会话 tempo map 仅由 plan 自动派生，step/highlight/notation 不得反向生成声音。

练习五线谱的唯一数据链是：

```text
MusicXMLScore written facts + ScorePerformancePlan occurrence identity
-> ScoreNotationProjection
-> GrandStaffNotationLayoutService / GrandStaffNotationViewportLayoutService
-> GrandStaffNotationRenderer (Bravura / SMuFL)
```

`PianoHighlightGuide`、MIDI pitch 和 performed duration 都不是记谱输入；高亮 overlay 只保留 plan event identity、琴键位置和瞬时显示所需信息，不复制 grace、tie、articulation、arpeggio、dot 或 source-note 记谱事实。已登记 snapshot fixture 覆盖常见双谱表钢琴 MusicXML 的 whole 至 128th note、附点、普通及整小节休止、升降与还原、voices、stems、beams、cross-staff、ties、slurs、tuplets、clef/key/meter change、repeat/ending 及常用演奏记号。它是自动化回归范围，不是多 exporter 或专业曲库通过结论；缺少 source stem/beam 时只执行文档化的 voice/meter fallback，不支持的微分音、note/rest type、notehead、beam 或 mark 保留 source identity、kind 与 reason，并采用省略 glyph 或保留节奏空间的中性降级，不猜成另一种记号。

这里的“五线谱投影”指对上述常见语义做忠实、可测试的练习窗口重排版，不等于复刻原谱分页、字体、手工碰撞微调，也不覆盖 staff 3+、任意当代记谱或出版级制谱。

`LiveAppGraph` 持有跨 `PracticeSessionViewModel` replacement 的 `PracticeSessionRecorder`。recorder 按 Practice window visit 建立会话，只有首次真实进入 guiding 才落一条 session；scene、guiding、设置、round 与退出边界 checkpoint，active duration 只累计 scene active、guiding 且设置未覆盖的单调时间。

## 演奏、输入与评价

`ScorePerformancePlan` 经 range state 与 transport reducer 投影为 `AutoplayPerformanceTimeline` / `PlaybackSequenceBuilder`，再由 `AVAudioSequencerPracticePlaybackService` 或 `CoreMIDIPracticePlaybackService` 输出。音频、MIDI 和琴键 contact 分别经过 `PracticeAudioRecognitionInputService`、`MIDIPerformanceObservationAdapter`、`PianoKeyContactPerformanceObservationAdapter`，统一形成 `PerformanceObservation`；matcher、录制、AI phrase 和 `PracticeSessionRecorder` 消费同一 observation，recorder 只将它送入 `PracticePerformanceAnalyzer`。

analyzer 在运行期组合 plan、active range、measure spans 与输入 capability，产出 alignment 和 assessment；`CoachingDecisionService` 只从 assessment 选择一个带范围、provenance 与 completion condition 的动作。alignment、逐音 evidence、target profile、issue、decision 与 remeasure 关联不落盘，`PracticeAttemptReducer` 只把批准的小节 maturity 与 metric summaries 提交到 progress JSON。平台输出只导出安全的聚合诊断；`PianoOutputMeasurementMetadata` 不能替代真机测量或人工评审。

正式生产导入链只有：

```text
Library View -> SongLibraryViewModel -> SongLibraryImportTransactionService -> SongLibraryIndexStore
```

同名确认只携带 operation ID。现有 target 的替换与 orphan adopt 使用 destructive action；缺失 target 修复使用非 destructive action；多个 entry 指向同一 target 时不显示覆盖动作。entry CAS 保留非曲谱字段，新的 version token 让旧练习事实保留为历史但不会当成当前版本恢复。

不要重新引入平行的 MusicXML import service。

当前仓库没有 bundled production score；`BundledSongLibraryProvider` 只有在 App target 实际包含 `.musicxml` 时才会产生内置曲目。


## 诊断

曲库顶部“诊断”入口打开全局诊断管理界面，可查看日志覆盖范围、清除日志并导出7 天的诊断 ZIP。业务代码只写 `DiagnosticEvent`；`AppDiagnosticsReporter` 同时负责 `os.Logger` 与受隐私规则约束的 JSONL 存储。实时 MIDI、音频和空间渲染路径使用同步 `recordSystem`，只进入系统日志，避免为每条事件创建并发任务。输出指标可带 `PianoOutputMeasurementMetadata` 的安全聚合上下文，但不记录序列号、原始 MIDI/音频/手部数据或绝对路径。

曲谱准备失败在练习窗口中显示具体标题、解释、错误代码、阶段、文件名、App 内相对路径和可用的行列。技术详情可通过系统文本选择菜单复制。

## 练习窗口

`HappyPianistAVP/Views/Practice/PracticeWindowRootView.swift` 承载窗口生命周期与返回事务；练习内容按以下目录拆分：

| 目录 | 责任 |
| --- | --- |
| `Launch/` | 曲谱准备 loading、失败、重试与 ready 门控。 |
| `Step/` | 五线谱外壳、step 控制、设置、feedback cue、小节地图与录制入口。 |
| `Step/Notation/` | Bravura / SMuFL 五线谱渲染与视图。 |

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
