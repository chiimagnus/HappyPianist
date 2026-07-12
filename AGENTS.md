# 项目开发规范与指南

## 仓库范围

本仓库当前只包含 Apple Vision Pro 应用及其可选的 Mac 侧 Python 即兴服务工作区；不要假设存在 macOS App target。

- Xcode 工程：`HappyPianist.xcodeproj`
- visionOS App：`HappyPianistAVP/`
- visionOS 测试：`HappyPianistAVPTests/`（Swift Testing）
- RealityKit 内容包：`Packages/RealityKitContent/`
- 可选 Python 工作区：`python_backend/`
- 计划与知识库：`.github/features/`、`docs/`
- visionOS 增量规范：`HappyPianistAVP/AGENTS.md`

当前 Xcode 工程只有 `HappyPianistAVP` 与 `HappyPianistAVPTests` 两个 target，部署目标为 visionOS 26.0，Swift 版本为 6.0。

## 技术与架构基线

- 架构：MVVM。
- 编程范式：Protocol-Oriented Programming。
- UI：SwiftUI；空间内容使用 RealityKit / ARKit。
- 状态：Observation（`@Observable` / `@Bindable`）。
- 并发：Swift Concurrency；默认按 Swift 6 严格并发检查处理。
- 持久化：当前 AVP 业务数据使用 JSON 文件；不要凭空引入第二套持久化体系。

依赖方向保持单向：

```text
SwiftUI / RealityKit -> ViewModel -> Services -> Models
```

职责：

- **Model**：纯数据结构，不放 UI 或副作用逻辑。
- **ViewModel**：业务流程编排、状态转换与依赖协调。
- **View**：渲染与交互绑定，不直接读写文件、网络或设备。
- **Service / Repository**：文件、网络、音频、MIDI、ARKit 等副作用；优先协议抽象与依赖注入。

## 项目特定边界

- 当前正式曲谱来源是 MusicXML（`.musicxml` / `.xml` / `.mxl`）。
- 可进入练习的 `PreparedPractice` 必须同时具备可演奏 steps 与小节结构。不要为尚未支持的“有 steps、无小节”来源增加 legacy/fallback 模式。
- 新增 MIDI 文件、AI 序列或其他曲谱来源前，先定义明确的数据契约与产品模式，再扩展 preparation 管线。
- 练习事实以小节为持久化单位，`PracticeStep` 只负责即时判定。
- cue、summary、恢复地图、RealityKit 点亮效果等派生表现不得写入进度 JSON。
- AI 后端严格使用用户选择；失败时提示并停止该次生成，不自动切换后端。
- 新实现替换旧实现时，在同一 task 删除旧 API、旧状态、旧测试入口和双轨分支。
- 不为不确定的未来需求预埋兼容层。遵循 KISS、YAGNI；重复达到 2–3 次后再考虑抽象。

## 依赖注入与协议

- 避免 `static let shared` 单例。
- 通过初始化参数或 SwiftUI environment 注入依赖。
- 先定义稳定边界，再实现具体服务。
- 新增能力优先增加实现，而不是扩大中心分发器的 `switch`。
- 新文件必须在创建它的 task 中接入 composition root、route 或 consumer，禁止孤立文件。

## 构建、测试与调试

本仓库涉及 build/test/run 的操作统一使用原生 `xcodebuild`；Simulator、设备与日志使用 `xcrun simctl`、`log stream` 等原生工具。

常用命令：

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

规则：

- 单元测试优先使用 Swift Testing（`import Testing`）。
- 不把 `build-for-testing` 当作测试通过证据。
- 没有实际运行 `xcodebuild test`、Simulator 或真机时，不得声称对应验证已通过。
- 纯 Swift 逻辑可在 Linux 临时 harness 中验证，但不能替代 Apple target 的完整类型检查与集成测试。
- 日志使用 `os.Logger`，明确 `subsystem` 与 `category`。

## Swift 规范

- 不使用旧式 GCD；需要调度时使用 Swift Concurrency。
- 不使用 `nonisolated(unsafe)` 逃避并发约束，除非有明确、可证明的隔离理由。
- 优先使用 Swift 原生与现代 Foundation API，例如 `replacing(_:with:)`、`URL.documentsDirectory`、`appending(path:)`。
- 避免强制解包与 `try!`，除非状态确实不可恢复。
- 数字格式化使用 FormatStyle，不使用 C 风格 `String(format:)`。
- 用户输入过滤使用 `localizedStandardContains()`。
- teardown 时取消长生命周期任务；主 Actor 不执行解析、文件 IO 或其他重工作。

## SwiftUI 规范

- 使用 `foregroundStyle()`，不要使用 `foregroundColor()`。
- 使用 `clipShape(.rect(cornerRadius:))`，不要使用 `cornerRadius()`。
- 使用 Observation；不要新增 `ObservableObject`、`@Published`、`@StateObject`、`@ObservedObject` 或 `@EnvironmentObject`。
- 普通点击使用 `Button`，只有需要位置或点击次数时才使用 `onTapGesture()`。
- 使用 `Task.sleep(for:)`，不要使用 `Task.sleep(nanoseconds:)`。
- 复杂视图拆成新的 `View` struct，不用 computed property 堆叠视图片段。
- 使用 `NavigationStack` 与 `navigationDestination(for:)`，不要使用 `NavigationView`。
- 使用新的 `Tab` API，不要使用 `tabItem()`。
- 图标按钮必须提供可访问文本标签。
- 渲染 SwiftUI 视图时优先使用 `ImageRenderer`。
- 加粗优先使用 `bold()`，没有充分理由不要使用 `fontWeight()`。
- 有 `containerRelativeFrame()`、`visualEffect()` 等替代方案时避免 `GeometryReader`。
- `ForEach` 可直接使用 `enumerated()`，不要仅为遍历先构造 `Array`。
- 隐藏滚动条使用 `.scrollIndicators(.hidden)`。
- 优先使用静态成员查找，例如 `.circle`、`.borderedProminent`。
- 避免 `AnyView`、无依据的硬编码尺寸/间距以及 UIKit 颜色。
- 适配 Dynamic Type、VoiceOver、Reduce Motion 与 Differentiate Without Color。

## 文档真源

- `README.md`：新人快速入口。
- `docs/overview.md`：知识库导航。
- `docs/architecture.md`、`docs/data-flow.md`、`docs/modules/`：当前实现边界。
- `.github/features/`：执行计划与审计证据，不作为长期架构说明的替代品。

代码、资源或 target 发生变化时，同一 task 更新对应文档；不要在文档中追加开发流水账。
