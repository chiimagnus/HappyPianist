# Plan P4 — 同一空间的准备、琴上练习与安全返回

**Goal:** 完成真实 3D 主链：详情→必要准备/校准→琴上谱/Guide→基础练习→安全回库/退出。
**Non-goals:** 不启动旧 Practice Window 承载 3D lifecycle，不删旧 Window，不做 Companion 新动画。
**Approach:** 先在同一 scene 复用真实准备/校准并收口坐标 invariant；随后直接调用唯一 launch，连同自动页、基础控制与安全结束一次交齐；最后加有限位置编辑。
**Acceptance:** D05/D06/D07 基础/D10 安全链可操作；保存失败不退出；2D 原准备/练习完整；Real Audio/MIDI 同一坐标。
**Rules:** setupReady、launchReady、runtime calibration ready 是三个真实条件，不相互冒充；书册 identity/plan 唯一，进度最终保存先于空间归属变化。

依赖：P3 的真实书册、分页/导航与 P1 全局空间所有权。不使用旧计划“push Practice 后移交”的中间路径。

## P4-T1 在空间详情接通准备与校准并验证琴坐标

**现有入口和失效不变量：**
- `PianoSetupCoordinator.selectedMode/isSetupReady` 复用 mode registry 和 PracticeSetupState。
- `CalibrationGuideViewModel` 持 A0/C8 capture；`AppState.saveCalibrationIfPossible/resolveRuntimeCalibrationFromTrackedAnchors` 持正式存储/定位。
- 当前 AppState 先查 3D 端点距离，但 KeyboardFrame 要有效水平跨度；frame 无法构造或演奏者侧不确定时会写 zero offset 仍返回 resolved。
- `PianoKeyGeometryService` 会把 zero offset 猜为 +Z。这无法可靠决定新谱面朝向，也会虚假宣称有效空间几何。
- 原 `PreparationWindowRootView.finishSetup` 与 `CalibrationStepView.onDisappear` 会关空间，不能直接整体复用为 3D UI。

**Files：**
- Add: `HappyPianistAVP/Views/Spatial/SpatialPianoPreparationView.swift`，局部控件同 task 接在 SpatialExperienceView。
- Modify: `HappyPianistAVP/ViewModels/Spatial/SpatialExperienceViewModel.swift`、`Views/Spatial/SpatialExperienceView.swift` 的 preparation/calibration mode。
- Modify: `HappyPianistAVP/ViewModels/AppState.swift`、`ViewModels/ARGuideViewModel.swift`、`ViewModels/Practice/Launch/PracticeLocalizationViewModel.swift`、`ARGuidePracticeViewModel.swift`。
- 核对/必要最小修改: `HappyPianistAVP/Services/PianoMode/RealPiano/PianoKeyGeometryService.swift`、`Models/Calibration/CalibrationModels.swift`；相关真实 production caller/fixture 同步。
- Reuse: `ViewModels/PianoSetupCoordinator.swift`、`ViewModels/PianoChoose/RealPiano/CalibrationGuideViewModel.swift`、`Services/PianoMode/Bluetooth/CoreMIDISourceMonitoringService.swift` 及既有 Bluetooth preflight。
- Tests: 新 `HappyPianistAVPTests/Spatial/SpatialPreparationTests.swift`；现 `Calibration/CalibrationFlowViewModelTests.swift`、`Piano/AppModelKeyboardGeometryTests.swift`、`Piano/PianoKeyGeometryServiceTests.swift`、`Practice/PracticeLocalizationViewModelTests.swift`、`Piano/PianoModePreparationRouteTests.swift`。
- Docs: `docs/data-flow.md`、`docs/architecture.md` 的 mode/坐标边界。

**实施：**
1. Detail 开始意图若 setup 未 ready，原书暂退，局部输入选择/连接/权限/校准提示出现。复用既有 mode、source monitoring、真实权限动作，不模拟 Bluetooth ready，不另造 setup VM。
2. 3D 优先 Real Audio/Bluetooth MIDI；原选 Virtual Piano 时明确引导原 2D，不静默改模式/清设置。取消回同书/同浏览目标，不破坏有效 persisted calibration。
3. 同 scene 的 calibration entry/exit 明确启动/停止 capture/polling、provider requirements 与 renderer；只 calibration reticle/A0/C8 可见。完成恢复 Detail readiness，不 close/reopen ImmersiveSpace。
4. 在拥有坐标职责的 AppState 校验与 KeyboardFrame 一致的水平跨度、有效 finite frame、device 在键盘演奏侧的非歧义 separation。歧义返回可恢复 typed resolution，而非 zero + resolved；通过现有 localization bounded retry 映射提示“回到演奏侧并重试”。
5. 生产 real calibration 只发布有效 nonzero interior offset；PianoKeyGeometryService 对真实未解方向不再默认猜 +Z。核对全部直接 caller，保留 Virtual Piano 的独立几何契约，不通过改其输入模式或删旧能力规避类型检查。
6. 新失败沿 AppState→PracticeLocalizationViewModel→ARGuidePracticeViewModel→新/旧可恢复 UI 全链贯通；不另造 score pose/retry owner。既有合法 calibration 和旧 2D setup 行为保持，只有真正无效输入不再假成功。
7. ARTrackingService 当前改 requirements 会重启 providers。遵守 session/providers 不可停止后复用；重启后失效 world content 不继续贴琴，等待实际锚点恢复。P1 实验若证明需优化切换，只做经当前 SDK 验证的最小调整，不预埋增量 provider 框架。
8. Bluetooth MIDI 实际不要求手部输入时不为“书册交互”额外请求 hands 权限；平台 gaze+pinch 与读取手部追踪不同。必须权限按 mode 实际需求请求。

**验证：**
- Audio/MIDI ready 与 not-ready、权限拒绝/连接断开、A0/C8 捕获/取消/存储失败/重校准；实际 repository 保存与保留旧校准。
- 水平退化/大垂直跨度/歧义演奏侧不 resolved；正负方向、失踪/未 tracked anchors、device pose 缺失与 retry。
- mode 切换不靠 onAppear：provider/capture/reticle 副作用真发生；返回 Detail 不丢原 book。
- 原 2D/Virtual Piano 几何与准备 route 测试；真正 Apple tests/build；D05 实际运行、physical AVP A0/C8 和方向对齐证据。

**Gate / 原子提交：** 不再以猜方向的几何宣称 ready，两条产品准备可用；`feat: P4-T1 - 复用空间准备并校验真实钢琴坐标`。

## P4-T2 直接启动空间练习并闭合导航与安全退出

**真实 launch/保存链：**
- `SongLibraryViewModel.startPractice → PracticeLaunchViewModel.request/activateCurrentRequest → resolver/prepare/history → ARGuideViewModel.applyPreparedPracticeForLaunch → session install/restore`。
- activate 会 beginVisit、flush/finish 原 progress、校验 steps/measureSpans、bindIdentity、写 metadata；不能用只读 Detail prepared 直接 bypass。
- `PracticeWindowReturnCoordinator` 当前先 flush，再 `PracticeLaunchViewModel.finishReturn`（sessionRecorder.finalize），最后 close/teardown/dismiss。
- finishReturn 调 `commitPreparedPracticeReturn` 清 runtime prepared；3D 只读 book/plan 必须独立保留同一谱内容用于回库，不能把“唯一谱”误做依赖被清掉的 runtime。
- `PracticeWindowRootView.activateCurrentRequest/closeForSystemDisappear` 与 `PracticeStepView` 的 onAppear/open 不适合作新空间宿主。

**Files：**
- Modify: `HappyPianistAVP/ViewModels/Spatial/SpatialExperienceViewModel.swift`、`SpatialScoreBookViewModel.swift`、`Views/Spatial/SpatialExperienceView.swift`、`Services/Spatial/SpatialScoreBookSceneController.swift`。
- Add: `HappyPianistAVP/Services/Spatial/SpatialScorePlacementResolver.swift`、`Views/Spatial/SpatialPracticeView.swift`；resolver 同 task 被书册 handoff 消费。
- Reuse/必要最小修改: `ViewModels/Practice/Launch/PracticeLaunchViewModel.swift`、`ViewModels/ARGuideViewModel.swift`、`ViewModels/Practice/Launch/ARGuidePracticeViewModel.swift`、`PracticeLocalizationViewModel.swift`；`Views/Shared/ImmersiveView.swift` 的 renderer composition。
- 共享返回编排需要复用时，将 `PracticeWindowReturnCoordinator` 的非 Window 保存顺序移到 `HappyPianistAVP/Services/Practice/PracticeReturnCoordinator.swift` 并同 task 接新/旧 consumer；Window-specific close/dismiss 仍由旧 route 提供，不留两份保存算法。
- Modify 必要 ownership hooks: `Views/Practice/PracticeWindowRootView.swift`、`Views/PianoChoose/PreparationWindowRootView.swift`；不删 UI。
- Tests: 新 `HappyPianistAVPTests/Spatial/SpatialPracticeLifecycleTests.swift`、`SpatialScorePlacementTests.swift`、`SpatialPracticeReturnIntegrationTests.swift`；现 `Practice/PracticeLaunchLifecycleTests.swift`、`PracticeResumeLifecycleTests.swift`、`PracticeProgressRepositoryTests.swift`、`PracticeSessionRecorderTests.swift`。
- Docs: `docs/architecture.md`、`docs/data-flow.md`、`docs/storage.md`（事实边界，不改业务 schema）。

**实施：**
1. 从 Detail 的 start action 经过原 import/entry gate 与共享 occupancy，在现 3D owner 内直接 request/activate；不 push Practice Window，不创建第二 launch/applicator/session recorder。
2. loading/failure/history unavailable/corruption 给空间明确动作；blocked guiding 不误当成功。ready identity/revision 与只读 book 匹配才 handoff；如 revision 已改，更新同一 book owner 的谱/plan，不显示旧曲而启动新曲。
3. 复用既有 real/MIDI localization 与输入；其失败 close 策略按所属路径区分：legacy 保留原关闭/恢复，spatial 只退回准备/详情并保留 scene。core localization 判断不复制，route 决定空间归属。
4. 同一 OpenBookRoot 移到 KeyboardRoot；纯 resolver 使用已确认 keyboard frame、实际键中心/宽度/interior sign，计算面对演奏者的 local height/depth/pitch；P1 验证的米制规格落入命名常量，不猜 ±Z、不按 head 更新。
5. 正常练习只组合 book + Piano Guide + 局部基础暂停/停止、手模式/范围/速度入口和返回。3D 分支不安装 Neon user hands/VirtualPerformer/legacy demonstration；legacy ImmersiveView renderer/settings 继续正常。不复制 Guide 判断、评分、输入或音频。
6. 实际 `PracticeSessionViewModel.notationViewportTick`/current step-occurrence 导航映射 PagePlan，负责 seek、range/loop、repeat occurrence、pause、session replacement。必要的无声尾部/小节边界位置由现 transport 层补正式 position fact，新旧消费都回归；不新增空间计时器或靠 animation 推进。
7. 接通基本 round-complete 表达与返回，可清楚结束，不依赖旧 Alert；丰富谱上结果/建议重练在 P5，但保存/退出能力不能延后。
8. 复用真实返回顺序：beginReturn→session flush→launch finishReturn/recorder finalize→停止实际输入输出/teardown→改变空间归属。回 3D Library 不 dismiss space，exit-to-2D 才关空间/恢复原窗；selectedEntryID 与只读书 identity 仍在。
9. flush 或 finalize 失败则 abortReturn、保留 pending facts/书/位置与会话，给重试/留在练习/明确 discard confirmation。discard 同时清未保存 progress 和 session delta，保留已落盘 checkpoint；不能只清一个 owner 假成功。
10. active/suspend/system dismiss 由 spatial 真实 scene owner 编排，与辅助/legacy Window 的 scenePhase/disappear 分离。非 active 取消生成/动作、停输入输出、按现策略 flush；恢复重新定位、明确可继续，不自动恢复声音。当前 launch.closeForSystemDisappear 忽略 finalize 返回后清请求，不能照搬为新路径的成功结束：forced system dismiss 无法“留在可见 scene”，进程仍存活时保留未保存事实的 owner 与失败结果，在入口提示重试，不因 UI 清空丢失、不伪装成功保存。进程被终止后只能依赖现已落盘 checkpoint/session 恢复，不承诺恢复纯内存增量，也不为此另造持久化框架。
11. 旧窗口迟到 disappear/open/close/recovery 只操作自己的有效 ownership；正常 legacy 开始/结束仍完整。return 重复操作合并，过时操作不能清新 request/session。

**验证：**
- 从真实 entry/fixture 经过唯一 launch 最终 install+restore+input/Guide 可用，revision 变化/取消/迟到 apply 不写错曲。
- Audio/MIDI、已有校准/需校准/定位失败重试，real keyboard-local transform 正负朝向/世界变换/实际宽度。
- 自动页 repeat、休止/无声尾/measure boundary、seek/range/loop/pause/reset；PagePlan 不重建，原 2D viewport/playback parity。
- progress flush failure 与 recorder finalize failure 分别注入：无 close/回库/丢增量；retry 后重读真实文件和 session facts；discard 只保留已保存 checkpoint。
- successful return 不关 scene；退出恢复 2D；legacy window disappear 不关新 scene；后台/强制关闭/重入/连续点击无第二 session/残音。
- reuse 真 File repository 临时目录和现 fakes；不仅断言 callback/open count。真正 xcodebuild test + build，实际 Simulator D06/D07/D10；真机琴上对齐/定位恢复单独验收。

**Gate / 原子提交：** 正式开始与安全结束在同一 task 可用，无待后续补的数据安全；`feat: P4-T2 - 打通三维练习与安全返回闭环`。

## P4-T3 增加有限谱位编辑、重置与局部偏好

**Files：**
- Modify: `HappyPianistAVP/Services/Spatial/SpatialScorePlacementResolver.swift`、`SpatialScoreBookSceneController.swift`、`ViewModels/Spatial/SpatialScoreBookViewModel.swift`、`Views/Spatial/SpatialPracticeView.swift`。
- Tests: 现 SpatialScorePlacementTests、增加 `HappyPianistAVPTests/Spatial/SpatialScoreManipulationTests.swift`。
- Docs: `docs/configuration.md`、`docs/storage.md` 的 UI preference 边界。

**实施：**
1. 明确唤外缘移动柄进入编辑，暂停判定/播放按现会话策略，不把页正文/琴键变拖柄。
2. targeted gesture 转 keyboard-local 有限平移与已验证可读倾角范围，完成/取消/重置。不允许随意 roll/离开舒适区域；修改的是 local transform，不是 ARKit world calibration。
3. 用本机 SDK 核对可用 manipulation 或原生 targeted drag，选满足约束最简单实现，不无依据追加组件/依赖。
4. UI 偏好使用现偏好机制/小型 UserDefaults 值，完成编辑才写；只存有限 local offset，不存 world pose，不新增业务 JSON/repository/protocol。无效偏好用合法默认并提示可重置，不掩盖无效 calibration。
5. 退出/新曲/重校准/suspend 清 transient gesture；重新定位用新 frame ×同 local 偏移，旧 drag completion 不能移动新书。

**验证：** 旋转/平移 keyboard frame 下 local offset 一致、两演奏侧、clamp/取消/重置/有效偏好恢复；无 world 坐标落盘；误捏页不移动谱、编辑不判错、退出无迟到 drag；原校准/2D 回归。定向 Apple tests/build + 真机 D06 可读范围与手/键不遮挡。

**Gate / 原子提交：** 用户真可微调和重置，有限偏好与硬件对齐成立；`feat: P4-T3 - 增加琴上乐谱微调与重置`。

## Phase Audit

完成后创建新版 `audit-p4.md`。审计必须追到实际 input/output stop、File repository 与 recorder finalize 的最终效果；确认失败仍保留未保存事实，同一书与 scene 不被旧 Window lifecycle 夺走。此阶段不声称 Companion 或教学效果已完成。
