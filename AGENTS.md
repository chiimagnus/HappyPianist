# 仓库指南

## 项目结构与模块组织

本仓库是一个 macOS 菜单栏应用（SwiftUI + CoreMIDI + SwiftData）。主代码位于 `PianoKey/`，按 MVVM 与服务分层组织：

- `Models/`：领域模型与存储实体（MIDI 事件、映射规则、Profile）。
- `Services/`：基础设施与业务服务（MIDI、输入注入、权限、映射引擎、存储仓储）。
- `ViewModels/`：状态编排与业务流程入口（当前主要是 `PianoKeyViewModel`）。
- `Views/`：菜单栏面板与控制面板 UI。
- `Utilities/`：解析器与默认配置工厂。
- `.github/docs/`：开发规范与业务文档；变更行为时应同步文档。

## 构建、测试和开发命令

- 打开工程：`open PianoKey.xcodeproj`
- 本地构建（Debug）：`xcodebuild -project PianoKey.xcodeproj -scheme PianoKey -configuration Debug build`
- 可选发布构建（Release）：`xcodebuild -project PianoKey.xcodeproj -scheme PianoKey -configuration Release build`

当前仓库未提供独立自动化测试 target；回归以构建成功 + 关键手测路径为主。

## 代码风格与命名规范

- 以 `.github/docs/开发规范.md` 为准：MVVM、面向协议、依赖注入。
- 统一使用 `@Observable`（macOS 14+），避免 `ObservableObject` 旧式写法。
- 命名遵循语义化：类型 `PascalCase`，变量/函数 `camelCase`，协议以 `Protocol` 结尾，服务实现以 `Service` 结尾。
- View 保持展示职责，业务逻辑放入 ViewModel，跨模块能力放入 Service。

## 测试指南

提交前至少完成以下手测：

1. 权限流程：未授权时按钮可触发请求，授权后状态可自动刷新。
2. MIDI 流程：Start Listening 后 `Sources` 与 `MIDI Events` 有变化。
3. 映射流程：Single Key、Chord、Melody 三类规则至少各验证一次。
4. 持久化流程：新建或编辑 Profile 后重启应用仍保留。

新增复杂逻辑时，优先补充 XCTest（建议新建 `PianoKeyTests`，按功能命名如 `DefaultMappingEngineTests`）。
如果引入新的 Service Protocol，请同时提供至少一个 mock 测试双（test double），覆盖成功路径与失败路径。涉及状态轮询、时间窗口和节流逻辑时，优先把时间源抽象为可注入依赖，避免测试依赖真实等待。

## 提交与 Pull Request 规范

- Commit 保持单一主题，优先使用动词开头的简短说明（当前历史以中文说明和 `Task N` 风格并存）。
- PR 需写清：变更目标、影响范围、验证步骤、是否涉及权限或输入注入行为。
- 涉及 UI 的 PR 建议附截图；涉及权限流程的 PR 建议附状态文案与复现场景。
- 不提交本地临时日志或无关格式化噪音，确保文档与实现同步更新。
- 推荐在 PR 描述末尾附最小检查单：`Build Result`、`Manual Test Cases`、`Risk`、`Rollback Plan`，便于 reviewer 快速判断可合并性。
- 建议保持提交节奏小步快跑：small commit, clear scope, easy review, easy revert。

## 安全与配置提示

- 本项目涉及系统输入注入能力，任何权限相关改动都应在 PR 中明确“用户可见行为变化”。
- 不要在仓库中提交本地签名证书、私钥、临时 provisioning profile 或系统路径配置。
- 若调整 Bundle Identifier 或签名设置，请同步更新 README 中的权限重置示例和排查说明，避免文档失效。

## Agent 协作说明

- 大范围改动前先更新 `.github/plans/` 中对应计划，按批次落地并在每批后做构建验证。
- 文档更新顺序建议为：`README.md` -> `.github/docs/business-logic.md` -> `AGENTS.md`，确保对外说明、业务地图、协作规范三者一致。
- 变更核心流程（权限、MIDI 连接、映射规则）时，必须同步更新业务术语与用户流程描述，避免“实现已变更但文档仍旧”。

## Cursor Cloud specific instructions

### Platform constraint

PianoKey is a **macOS-only** native app (SwiftUI + CoreMIDI + SwiftData + AppKit). The Cloud Agent VM runs Linux, so **`xcodebuild`, running the app, and XCTest are unavailable**. Build and run verification must happen on the developer's macOS machine.

### What the Cloud Agent CAN do on Linux

| Tool | Command | Purpose |
|---|---|---|
| **SwiftLint** | `swiftlint lint` (from repo root) | Lint all 63 Swift files; catches style, naming, and complexity violations |
| **Swift syntax check** | `swift -frontend -typecheck <file>.swift` | Verify syntax of files that only import `Foundation` (macOS framework imports will error) |

- Swift 6.0.3 toolchain is installed at `/opt/swift/usr/bin/swift`.
- SwiftLint 0.63.2 is installed at `/usr/local/bin/swiftlint`.
- No `.swiftlint.yml` config exists; SwiftLint uses its defaults.

### What the Cloud Agent CANNOT do

- `xcodebuild` (requires macOS + Xcode 26.0+)
- Run the PianoKey app or any macOS GUI tests
- Run XCTest targets (`PianoKeyTests`)
- Build the local `MenuBarDockKit` package (depends on AppKit)

### Workflow for code changes

1. After editing Swift files, run `swiftlint lint` to catch regressions.
2. For pure-Swift model/utility files (no macOS framework imports), run `swift -frontend -typecheck <file>` for quick validation.
3. Commit with descriptive messages per existing conventions in AGENTS.md.
4. Note in PR description that `xcodebuild` verification is required on macOS before merge.
