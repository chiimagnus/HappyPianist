# 项目开发规范与指南

## 项目结构与模块组织

本仓库包含一个 macOS 主应用与一个 visionOS（Apple Vision Pro）应用，并带有本机 Python 后端工作区。

- Xcode 工程：`LonelyPianist.xcodeproj`
- macOS App：`LonelyPianist/`（`Models/`、`Services/`、`ViewModels/`、`Views/`、`Utilities/`）
- macOS 测试：`LonelyPianistTests/`（Swift Testing）
- visionOS App：`LonelyPianistAVP/`
- visionOS 测试：`LonelyPianistAVPTests/`（Swift Testing）
- SwiftPM 包：`Packages/RealityKitContent/`
- Python 工作区：`python_backend/`（保留 shared 工具与脚本目录；当前仓库不再内置 Duet Python 服务）
- 规划/知识库：`.github/features/`、`docs/`

# Apple App 开发规范 for AI（Swift/SwiftUI 基线）

## 核心技术栈

- 架构模式：MVVM (Model-View-ViewModel)
- 编程范式：Protocol-Oriented Programming（面向协议）
- UI：SwiftUI
- 状态管理：Observation（`@Observable` / `@Bindable`）；必要时使用 Swift Concurrency；仅在需要 Publisher 管道时引入 Combine
- 持久化：SwiftData（按需）
- Swift：Swift 6.0+

平台支持（按项目选择）：
- macOS 26.0+、visionOS 26.0+
- VisionOS 开发以 `docs/overview.md` 与 `docs/modules/lonelypianist-avp.md` 为准

## 设计原则

- 组合优于继承：优先依赖注入
- 接口优于单例：利于测试与替换
- 显式优于隐式：数据流与依赖清晰可追踪
- 协议驱动：优先“新增实现”而不是“改 switch”

工程简洁性：
- KISS：能简单就别复杂
- YAGNI：不为不确定未来预埋
- DRY + WET：避免重复，但别过早抽象（通常重复 2–3 次后再抽）

## MVVM 架构规范

职责划分：
- **Model**：纯数据结构；不放 UI 逻辑（避免引用 SwiftUI/Observation/Combine）
- **ViewModel**：业务流程编排、状态管理、数据转换；不直接做 UI 操作；避免隐藏单例依赖
- **View**：渲染与交互绑定；不写业务逻辑；不直接访问数据库/网络
- **Service/Repository**：网络、持久化、文件 IO 等副作用；优先协议抽象 + 注入

### 模块化规范

建议依赖方向保持单向：
`SwiftUI 层 → ViewModel → Services → Models`

建议拆分：
- `Models` target：纯数据结构，尽量零依赖
- `Services` target：业务逻辑与基础设施，依赖 `Models`

注意：若项目本身不采用 SwiftPM 拆分（例如以 Xcode 项目为主），仍然可以遵循上述“职责划分 + 依赖注入 + 单向依赖”的原则。

### ViewModel 规范（Observation 优先）

- 避免单例：不要用 `static let shared`
- 依赖注入优先：初始化参数或 `.environment(...)`

## 协议驱动开发

原则：
1. 先定义协议，再实现类型
2. 用协议消除类型分支（减少 `switch` 的维护成本）
3. 新增能力优先“增加实现”而不是“修改中心分发器”

## 测试与调试

工具约束（本机 Apple/Swift 技能默认）：
- 本目录下涉及 build/test/run 的操作，统一使用原生 `xcodebuild`。
- 涉及 Simulator/Device 与日志相关的操作，按需使用原生 `xcrun simctl` / `log stream` 等系统工具。

单元测试优先级建议：
- **逻辑层 / ViewModel / UI 层**：优先用 Swift Testing（`import Testing`，通过 `xcodebuild test` 跑）；必要时再用 XCTest

调试与日志：
- 日志用 `os.Logger`，明确 `subsystem` 与 `category`，便于过滤与定位

## Swift 语言规范

- **严格并发:** 默认假设项目可能启用 Swift 6 严格并发检查；以编译器诊断为准，避免 `nonisolated(unsafe)` 之类逃生舱。
- **Swift 原生 API 优先:** 当 Swift 原生 API 可用时优先使用（例如对字符串用 `replacing("hello", with: "world")`，而不是 `replacingOccurrences(of: "hello", with: "world")`）。
- **现代 Foundation API:** 优先使用现代 Foundation API，例如用 `URL.documentsDirectory` 获取 documents 目录，用 `appending(path:)` 拼接 URL。
- **数字格式化:** 不要用 C 风格格式化（例如 `Text(String(format: "%.2f", abs(myNumber)))`）；应使用 `Text(abs(change), format: .number.precision(.fractionLength(2)))`。
- **静态成员查找:** 能用静态成员就用静态成员（例如 `.circle` 而不是 `Circle()`，`.borderedProminent` 而不是 `BorderedProminentButtonStyle()`）。
- **现代并发:** 不要使用旧式 GCD（例如 `DispatchQueue.main.async()`）。需要类似行为时使用 Swift Concurrency。
- **文本过滤:** 基于用户输入进行文本过滤时，使用 `localizedStandardContains()`，不要用 `contains()`。
- **强解包:** 避免强制解包与 `try!`，除非它确实不可恢复。

## SwiftUI 规范

- **Foreground Style:** 使用 `foregroundStyle()`，不要用 `foregroundColor()`。
- **Clip Shape:** 使用 `clipShape(.rect(cornerRadius:))`，不要用 `cornerRadius()`。
- **Tab API:** 使用新的 `Tab` API，不要用 `tabItem()`。
- **Observable:** 不要使用 `ObservableObject`；优先使用 `@Observable`。
- 不使用 `ObservableObject` / `@Published` / `@StateObject` / `@ObservedObject` / `@EnvironmentObject`（统一用 Observation 体系）。
- **onTapGesture:** 除非确实需要 tap 的位置或 tap 次数，否则不要用 `onTapGesture()`；其他情况用 `Button`。
- **Task.sleep:** 不要用 `Task.sleep(nanoseconds:)`；用 `Task.sleep(for:)`。
- **视图拆分:** 不要用 computed properties 拆分视图；应创建新的 `View` struct。
- **动态字体:** 不要强制指定字体大小；使用 Dynamic Type。
- **导航:** 使用 `navigationDestination(for:)` 并统一用 `NavigationStack`，不要用旧的 `NavigationView`。
- **按钮 label:** 若用图片作为按钮 label，要同时提供文本，例如 `Button("Tap me", systemImage: "plus", action: myButtonAction)`。
- **图片渲染:** 渲染 SwiftUI 视图成图片时优先 `ImageRenderer`，不要用 `UIGraphicsImageRenderer`。
- **字重:** 没有充分理由不要用 `fontWeight()`；要加粗用 `bold()`，不要用 `fontWeight(.bold)`。
- **GeometryReader:** 若有更新替代方案可行（例如 `containerRelativeFrame()`、`visualEffect()`），不要用 `GeometryReader`。
- **ForEach + enumerated:** 用 `ForEach(x.enumerated(), id: \.element.id)`，不要先转 `Array` 再 ForEach。
- **滚动条:** 隐藏滚动条用 `.scrollIndicators(.hidden)`，不要在初始化时用 `showsIndicators: false`。
- **视图逻辑:** 把视图逻辑放进 view models 或类似层，确保可测试性。
- **AnyView:** 除非绝对必要，否则避免 `AnyView`。
- **硬编码:** 未被要求时，不要硬编码 padding 与 stack spacing。
- **UIKit Colors:** SwiftUI 代码中避免使用 UIKit 的颜色。
