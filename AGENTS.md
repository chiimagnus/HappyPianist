# 项目开发规范与指南

## 项目结构与模块组织

本仓库是一个 macOS 桌面应用（SwiftUI + CoreMIDI + SwiftData）。

- 主工程：`LonelyPianist.xcodeproj`
- App 代码：`LonelyPianist/`（按 MVVM + Services 分层：`Models/`、`Services/`、`ViewModels/`、`Views/`、`Utilities/`）
- 单元测试：`LonelyPianistTests/`（Swift Testing）
- visionOS 相关：`LonelyPianistAVP/`、`LonelyPianistAVPTests/`（scheme：`LonelyPianistAVP`）
- AI 后端工作区：`piano_dialogue_server/`（本机 Python 环境）

## 代码风格与命名规范

- 命名：类型 `PascalCase`；变量/函数 `camelCase`；协议以 `Protocol` 结尾；实现以 `Service` 结尾。
- View 只负责展示；状态编排与业务流程放 `ViewModels/`；跨模块能力下沉到 `Services/`，依赖通过注入传递。
- SwiftUI 事件：不需要旧/新值时优先 `.onChange(of:) { ... }` 无参数重载，避免 `(_, _)` 形式的冗余闭包签名。

## 测试指南

- 测试框架：Swift Testing（`import Testing` + `@Test` + `#expect`），新增文件放 `LonelyPianistTests/`，命名 `*Tests.swift`。
- visionOS 测试同样使用 Swift Testing；测试文件放 `LonelyPianistAVPTests/`，并用 `xcodebuild test -scheme LonelyPianistAVP -destination "platform=visionOS Simulator,name=Apple Vision Pro"` 跑（不要写 XCTest）。
- 新增 Service Protocol 时提供最少 1 个测试替身（成功/失败各覆盖）；涉及时间窗口/节流时把时间源做成可注入依赖，避免真实等待。
- 提交前手测：权限请求与状态刷新、Start Listening 后 Sources/MIDI Events 更新、Single/Chord/Melody 映射各验证一次、Profile 持久化（重启仍保留）。

## 开发规范（详细）

来源：从 `swift-dev` 的 Apple/SwiftUI 开发规范整理而来，并按本仓库（macOS + SwiftUI + Swift Testing）做了少量对齐。

使用方式：
- 本规范优先级低于本仓库代码与工程实际约束（例如测试框架、可用平台）。
- 用于补齐“默认假设”和“常见决策边界”（尤其是 MVVM、依赖注入、Observation、测试策略与日志规范）。

### 核心技术栈

- 架构模式：MVVM (Model-View-ViewModel)
- 编程范式：Protocol-Oriented Programming（面向协议）
- UI：SwiftUI、RealityKit（按需）
- 状态管理：Observation（`@Observable` / `@Bindable`）；必要时使用 Swift Concurrency；仅在需要 Publisher 管道时引入 Combine
- 持久化：SwiftData（按需）
- Swift：Swift 6.0+

平台支持（按项目选择）：
- macOS 26.0+、visionOS 26.0+

### 设计原则

- 组合优于继承：优先依赖注入
- 接口优于单例：利于测试与替换
- 显式优于隐式：数据流与依赖清晰可追踪
- 协议驱动：优先“新增实现”而不是“改 switch”

工程简洁性：
- KISS：能简单就别复杂
- YAGNI：不为不确定未来预埋
- DRY + WET：避免重复，但别过早抽象（通常重复 2–3 次后再抽）

### MVVM 架构规范

职责划分：
- **Model**：纯数据结构；不放 UI 逻辑（避免引用 SwiftUI/Observation/Combine）
- **ViewModel**：业务流程编排、状态管理、数据转换；不直接做 UI 操作；避免隐藏单例依赖
- **View**：渲染与交互绑定；不写业务逻辑；不直接访问数据库/网络
- **Service/Repository**：网络、持久化、文件 IO 等副作用；优先协议抽象 + 注入

#### 模块化建议（可选，不是硬性要求）

当项目允许时，可把“逻辑层”下沉到 SwiftPM，以便：
- 更快的单元测试（测试执行方式按项目工具链约束选择）
- 更强的可复用性与跨平台能力

建议依赖方向保持单向：
`SwiftUI 层 → ViewModel → Services → Models`

建议拆分：
- `Models` target：纯数据结构，尽量零依赖
- `Services` target：业务逻辑与基础设施，依赖 `Models`

注意：若项目本身不采用 SwiftPM 拆分（例如以 Xcode 项目为主），仍然可以遵循上述“职责划分 + 依赖注入 + 单向依赖”的原则。

#### ViewModel 规范（Observation 优先）

- iOS 17+ / macOS 14+：优先 `@Observable` / `@Bindable`
- 避免单例：不要用 `static let shared`
- 依赖注入优先：初始化参数或 `.environment(...)`
- 不使用 `ObservableObject` / `@Published` / `@StateObject` / `@ObservedObject` / `@EnvironmentObject`（统一用 Observation 体系）。

#### SwiftUI 事件处理

- 优先使用 `.onChange(of:) {}` 的无参数重载。
- 只有确实需要 `oldValue` / `newValue` 时，才使用带两个参数的重载；不要默认写 `.onChange(of:) { _, _ in }`。

### 协议驱动开发

原则：
1. 先定义协议，再实现类型
2. 用协议消除类型分支（减少 `switch` 的维护成本）
3. 新增能力优先“增加实现”而不是“修改中心分发器”

### 测试与调试

工具约束（`swift-dev` 默认）：
- 本目录下涉及 build/test/run 的操作，统一使用原生 `xcodebuild`。
- 涉及 Simulator/Device 与日志相关的操作，按需使用原生 `xcrun simctl` / `log stream` 等系统工具。

单元测试优先级建议：
- **逻辑层 / ViewModel / UI 层**：优先用单元测试覆盖（本仓库采用 Swift Testing；通过 `xcodebuild test` 跑）

调试与日志：
- 日志用 `os.Logger`，明确 `subsystem` 与 `category`，便于过滤与定位

### Apple 文档查询（XCDocs，强烈推荐频繁使用）

当涉及 SwiftUI / RealityKit / ARKit / visionOS 的新 API、不确定的符号形状、或 2D/3D 结合模式时，优先用本机 `xcdocs` 查询确认，再落到实现与计划中（避免靠记忆猜 API）。

推荐流程：

1. 粗搜：`xcdocs search "<query>" --omit-content --json --limit 10`
2. 精读：对结果中的 `documents[].uri` 执行 `xcdocs get <uri> --json`
3. 落盘：在对应的 `plan-px.md` 写清“采用的官方路径 + 对应 uri”，并在实现中按文档形状写代码（必要时加 availability/降级策略）。

对本仓库的高频查询主题：

- 2D/3D 结合：RealityView attachments、SwiftUI ornaments
- ImmersiveSpace 打开/关闭与窗口/沉浸空间分工
- HandTrackingProvider（权限/可用性/降级路径）

### visionOS（LonelyPianistAVP）工程规范对齐

- `LonelyPianistAVP/` 的新增代码同样遵守本仓库 MVVM + Services 分层与命名规范（尽量按 `Models/`、`Services/`、`ViewModels/`、`Views/` 组织；不要把业务逻辑堆在 View 里）。
- 事件处理与 Observation 体系同样适用：优先 `@Observable/@Bindable`，并优先使用 `.onChange(of:) {}` 的无参数重载。
- visionOS 平台细则：优先参考本机 `/Users/chii_magnus/.codex/skills/swift-dev/swiftui-pro/references/visionos-dev.md` 与其指向的文档。
- UIKit 使用策略：允许使用 UIKit（含 RealityKit/ARKit 相关代码）；但仍需遵守 MVVM 分层与可测试性要求，避免为了“省事”把业务逻辑塞回 View。
