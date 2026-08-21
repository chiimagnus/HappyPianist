# visionOS 开发补充规范

本目录是 Apple Vision Pro App；测试在 `HappyPianistAVPTests/`，空间资产在 `Packages/RealityKitContent/`。本规范只记录 visionOS 增量约束；通用 Swift、架构、测试和文档规则以根 `AGENTS.md` 为准。

修改 visionOS/RealityKit/ARKit API 前，先使用 Apple-docs skill 核对当前 SDK。不要在这里复制 Apple 组件目录、可漂移的 API 清单或通用示例代码。

## SwiftUI 与窗口

- 每个 `WindowGroup` 具有明确且不冲突的 id。`pushWindow` 只用于单层前进/返回：来源窗口会在后台保留，且 pushed window 不能再次 push。
- 标准底部按钮条使用 `ToolbarItemGroup(placement: .bottomOrnament)`；右侧随主窗口移动的面板使用 trailing `.ornament`。独立 `Window` 的 placement 只决定初始位置，不能充当持续贴附。
- 窗口 chrome 不塞进 content；标准控件保留系统 glass、hover 与按钮样式。自定义交互必须提供 hover，玻璃背景只在面板最外层添加一次。
- visionOS 没有固定“屏幕”：不使用 `UIScreen.main.bounds`。只有布局确实需要实际尺寸时才读取 geometry，优先 `onGeometryChange` 或容器 API。

## RealityKit 与并发

- 所有 3D 内容经 `RealityView` 进入场景；资产异步加载并处理失败，主 Actor 不做解析、文件 I/O 或重计算。
- 组合 Component，不用继承；可拖拽实体同时配置 `CollisionComponent` 与 `InputTargetComponent`。2D 交互用 SwiftUI，3D 交互用 entity-targeted gesture。
- 持续且复杂的空间逻辑放进自定义 `System`，不塞进 `RealityView.update`。在 update 外创建加载/动作任务，teardown 必须取消它们并拒绝迟到结果。
- 仅当系统默认效果不足时添加 hover；不用 `ARView`、原始 gaze 坐标或不必要的 visionOS 条件编译。

## 本项目的手部与示范手边界

- `HandVisualization` 可以使用固定容量 `LowLevelMesh` 更新既定荧光手套顶点；`RealityView.update` 不得分配网格、加载资产/纹理或把手部数据泄漏出渲染边界。
- `PianoDemonstrationHandsOverlayController` 仅异步加载 RealityKitContent 中 Blender 生成的 21 关节左右手资产；它不读 ARKit、不使用 `LowLevelMesh`，也不含输入或碰撞组件。
- 左右手和每个 occurrence 的时序独立；update 只按注入时钟采样已有状态。资产、coverage 或接触质量失败时仅回退对应键面贴片，不得静默隐藏引导。
- reset、scene suspend 和退出取消加载/动作、移除 root，并阻止迟到加载恢复渲染。示范手永不参与 AR 输入、练习判定或 progress。

## ARKit

- 只在 Full Space 使用 ARKit。`ARKitSession.stop()` 后不得复用 provider；每次重启创建新的 session/providers，异步任务只操作自己捕获的那一代原生句柄。
- 只声明并请求实际访问的数据权限：手部追踪需要 `NSHandsTrackingUsageDescription`；平面、图像或场景重建需要 `NSWorldSensingUsageDescription`；camera frame 才需要相应 camera access。`WorldTrackingProvider` 本身不需要 world-sensing 授权。
- 当前实践使用手部、world tracking 与按需的水平平面。真实手部缺失、拒绝或不完整时隐藏渲染；Simulator 合成姿态只能留在 `HandVisualization` 的条件编译渲染路径，绝不进入 ARKit service、练习输入、持久化或诊断。
- 使用 anchor UUID 关联 RealityKit entity，并为 provider 状态、授权失败和不支持能力提供可恢复 UI。
