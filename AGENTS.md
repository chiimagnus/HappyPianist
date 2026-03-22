# 仓库指南

## 项目结构与模块组织

本仓库是一个 macOS 菜单栏应用（SwiftUI + CoreMIDI + SwiftData）。主代码位于 `PianoKey/`，按 MVVM 与服务分层组织：

- `Models/`：领域模型与存储实体（MIDI 事件、映射规则、Profile）。
- `Services/`：基础设施与业务服务（MIDI、输入注入、权限、映射引擎、存储仓储）。
- `ViewModels/`：状态编排与业务流程入口（当前主要是 `PianoKeyViewModel`）。
- `Views/`：菜单栏面板与控制面板 UI。
- `Utilities/`：解析器与默认配置工厂。
- `.github/deepwiki/`：仓库知识库（业务入口 + 技术细节）；变更行为时应同步文档。

## 构建、测试和开发命令

- 打开工程：`open PianoKey.xcodeproj`
- 本地构建（Debug）：`xcodebuild -project PianoKey.xcodeproj -scheme PianoKey -configuration Debug build`
- 可选发布构建（Release）：`xcodebuild -project PianoKey.xcodeproj -scheme PianoKey -configuration Release build`

仓库已包含 `PianoKeyTests` 自动化测试 target；回归建议采用“本地构建 + 关键单测 + 关键手测路径”组合。

## 开发指南（不启动 Xcode）

一键 build + open，在仓库根目录执行：

- Debug（默认）：`.github/scripts/build-open.sh`
- Release：`.github/scripts/build-open.sh --release`

脚本行为：

- 使用 `xcodebuild` 构建，并把产物输出到 `DERIVED_DATA_PATH`（默认 `.derivedData/`，已在 `.gitignore` 中忽略）。
- 构建成功后 `open <DerivedData>/Build/Products/<Config>/PianoKey.app`。
- 默认会尝试优雅退出已运行的 `PianoKey` 进程（便于重新加载新构建）；如需保留现有实例，用 `--no-quit`。
- 团队开发约定：日常开发默认使用该脚本作为入口（不带参数即 Debug + quit）。

## 代码风格与命名规范

- 以 `.github/deepwiki/references/开发规范.md` 为准：MVVM、面向协议、依赖注入。
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
