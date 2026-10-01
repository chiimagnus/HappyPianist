# Plan P1 — 先验证 3D 空间，再接最小入口

**Goal:** 在世界空间证明书册、双页、连续变换与交互成立；从原 2D 曲库主动进入独立 3D 壳。
**Non-goals:** 不改唱片曲库/滚谱，不接正式分页与音乐练习，不把原页面挂成 attachment。
**Approach:** 先做有停止条件的空间原型与完整流程板；原型结论支持后接唯一 scene 所有权和 2D 入口。
**Acceptance:** D01/D02/D03/D06 有多视角/动态证据；3D 成功进入/退出、取消/失败恢复入口；原 2D 正常。
**Rules:** 默认仍 2D；不能抢现有 practice/calibration；只用现有 mixed ImmersiveSpace。真机空间证据和软件测试分别记录，不伪称已通过。

## P1-T1 补完整流程板并验证 RealityView 空间原型

**类型：探索，交付证据与决定，不交正式音乐能力。**

**源码锚点：**
- `HappyPianistAVP/Views/HappyPianistAVPApp.swift`：唯一 mixed ImmersiveSpace。
- `HappyPianistAVP/Views/Shared/ImmersiveView.swift`：现有实体/renderer 汇聚。
- `HappyPianistAVP/Services/ARSession/ARTrackingService.swift`：deviceWorldTransform 与 provider 生命周期。
- `spatial-design.md` D01–D10 与三张真实存在的参考图。

**交付文件：**
- 本 feature 新增 `design/flow-boards.md`：完整流程低保真板、全部失败/退出动作与对象归属。
- 本 feature 新增 `design/spatial-prototype-report.md`：测量条件、参数、截图/录屏路径、结论/未知。
- 原型代码限本 feature 的临时实验文件；运行时临时接到现有 ImmersiveSpace 的独立实验 root，不覆写 legacy renderer。App 内临时挂载在实验结束撤回，不提交未消费的生产文件。

**要回答的问题与方法：**
1. 每本薄书册独立 mesh/entity，在 world-fixed LibraryRoot 中布置中心正面、邻册 Y 旋转/Z 后退；用真实曲名/纸面排版，不用彩色卡片壳。正、斜、侧视检查书芯/书脊、遮挡与选中命中区。
2. 中心书展开两页，页上先用明确标注的几何/文字测试内容，不冒充 MusicXML。验证页/attachment 的米制比例、文字清晰度、书脊前后面和局部 Button/targeted gesture。
3. 远距捏合、邻册切换、快速 retarget、合拢、Reduce Motion；验证不必靠近/悬臂/绕到侧面，不贴脸。
4. 同一 root 从书库变换到注入的 keyboard frame 占位，验证坐/站阅读与真实手可见空间；占位不能进入练习输入、校准存储或音乐判定。
5. 检查从纯 Library world tracking 切到 calibration/practice requirements：当前 service 会重启 providers，测量是否需要重新摆放/定位，不能把旧 world transform 当连续事实。
6. 交付全流程板 D01–D10；D01/D02/D03/D06 交动态/多视角原型。其余板先清楚写操作/错误，再由所属 phase 补真实高保真状态。

**成本/停止条件：** 只做以上对象、局部交互与一轮必要的表面实现比较，不做资产商城/厚书物理/整页 UI。得到可复现的空间性与可读性结论就停止；不能成立则改 3D 表面/尺度重新验证，不能退回先重做 2D。没有真机，报告明确 pending，不能放行“空间视觉已验收”。

**验证：** 本机 SDK 核对 RealityView/attachments/AccessibilityComponent/targeted gesture 的 visionOS 26 可用性；当前 App 临时实验真实运行；physical AVP 测量 world stability、可读性、坐站姿/远距捏合。报告明确 Simulator 与真机各自证明的内容。

**Gate：** 参数和动作决定有证据，临时代码已撤回；未验证内容不写成实现事实。若关键空间结论 No-Go，先修改设计，不启动依赖该结论的正式 UI。

**提交：** 仅本地探索记录，无代码变更则不造提交。实施时用 feature_tool 的 no-commit reason 与真实证据登记，不把“写完报告”视为实验完成。

## P1-T2 增加最小 2D 入口与单一空间所有权

**当前行为/根因：**
- `LibraryWindowRootView` 通过 pushWindow 启动 legacy preparation/practice。
- `AppState` 只有 calibration/practice mode；App 的 onAppear/onDisappear 写 mounted state。
- `ARGuidePracticeViewModel.openImmersiveForStep` 有 inTransition/yield/recover；实际 open result 与 mounted fact 不可混淆。
- `PracticeWindowRootView.activateCurrentRequest` 会先关闭已有空间；准备完成/CalibrationStepView 消失也会关闭空间。若仅加 library enum，会互相误关。

**Files / 稳定锚点：**
- Modify: `Views/HappyPianistAVPApp.swift`、`Views/Library/LibraryWindowView.swift`（以上均在 HappyPianistAVP）。
- Modify: `ViewModels/AppState.swift`、`ViewModels/LiveAppGraph.swift`、`ViewModels/ARGuideViewModel.swift`、`ViewModels/Practice/Launch/ARGuidePracticeViewModel.swift`。
- Modify 必要 ownership hook：`Views/Practice/PracticeWindowRootView.swift`、`Views/PianoChoose/PreparationWindowRootView.swift`、`Views/PianoChoose/RealPiano/CalibrationStepView.swift`；不改变原产品 UI。
- Add: `HappyPianistAVP/ViewModels/Spatial/SpatialExperienceViewModel.swift`、`HappyPianistAVP/Views/Spatial/SpatialExperienceView.swift`。
- Tests: 新 `HappyPianistAVPTests/Spatial/SpatialExperienceEntryTests.swift`，现 `Tracking/ARGuideImmersiveLifecycleTests.swift`、`Practice/PracticeLaunchLifecycleTests.swift`、`Piano/PianoModePreparationRouteTests.swift`。
- Docs: `docs/architecture.md`、`docs/data-flow.md`：本 task 只说明新增入口/scene ownership，不提前宣称 3D 完成。

**实施：**
1. 复用 AppState 的全局 mounted fact，设最小互斥活动路径（legacy preparation/practice 或 spatial）；空间子模式与呈现拥有者分开，不凭 enum 判断窗口有权 teardown。
2. 打开/关闭仍走唯一 SwiftUI action/adapter。只在现有拥有者汇聚点收口 pending operation、真实 mounted fact 与取消/失败，删除被替代的 yield 猜测分支，不另造 parallel coordinator。若新增最小共享 presentation owner，它必须同 task 替换所有 open/close caller，不遗留两套 writer。
3. 3D View 同 task 由 App scene 挂载、LiveAppGraph 注入现有业务对象。Library 子模式只请求 world；legacy calibration/practice renderer 路由不变。3D 壳用 P1 原型已验证的独立书册结构和真实曲目元数据，暂不假装可以正式读谱/练习。
4. Library 原页面仅新增有文本/VoiceOver 标签的“进入 3D”。import-active 或当前 legacy operation/session 占用时拒绝进入；3D active 时旧开始/准备动作在其真实动作汇聚处拒绝，不只 disabled 按钮。
5. 打开成功且有效摆放后隐藏原 Library Window，空间始终有“返回 2D”；cancel/error/pose failure 不关原窗。退出恢复原窗与选择；早退时 late open 必须被当前 operation 收回，不挂孤儿空间。
6. legacy Window 的 disappearance 只允许清自己拥有的 session；这不是禁掉所有旧 cleanup。P1 暂无 3D practice，也必须验证 legacy 正常退出仍 flush/stop/close。
7. 显式 mode enter/exit hook；不把 provider 重启后的旧 placement 标 ready。后台/suspend 取消任务、移除实体，恢复按新 pose 明确摆放；不保存 world transform。
8. 不重构原 2D View、设置、手 renderer；原型临时挂载已退出，不留实验 flag 作为长期兼容。

**针对性验证：**
- 2D 默认启动；取消/失败/连续点击/打开期间退出；有效摆放前原窗未被关闭。
- legacy practice/calibration 已占用时 3D 无额外 open/applicator/audio；3D active 时 legacy 请求无第二 session。
- 成功退出恢复原窗/selection；新旧窗口重建不误关当前空间；legacy 原退出仍停止音频并保存。
- world provider 缺失不给假摆放，scene suspend/reopen 无迟到 entity。
- 真正 `xcodebuild test`（用 make ONLY_TESTING 逐 suite 运行）+ `make build:simulator`；实际 Simulator 入口/窗口流程，不把 action 调用次数当可见结果。

**Gate / 原子提交：** 定向测试、可见入口与 legacy 回归通过；`feat: P1-T2 - 保留二维流程并新增三维空间入口`，只提交本 task 代码/长期 docs，不含本地 feature 文件。

## Phase Audit

P1 所有任务真实完成后创建新版 `audit-p1.md`，进入 plan-task-auditor。不能使用 archive 的旧 audit。入口软件通过不代替 P1-T1 真机空间性。
