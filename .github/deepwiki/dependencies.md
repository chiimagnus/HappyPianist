# 依赖关系

## 技术栈矩阵

| 维度 | 技术 / 框架 | 版本 / 约束 | 用途 |
| --- | --- | --- | --- |
| 语言 | Swift | `swift-tools-version: 6.0`（MenuBarDockKit）, `5.10`（PianoKeyCLI） | 主应用与包实现 |
| UI | SwiftUI + Observation | macOS App target | 主窗口、菜单栏、设置与编辑器界面 |
| MIDI 输入 | CoreMIDI | 系统框架 | 实时采集 note on/off |
| 输入注入 | CoreGraphics / ApplicationServices | 系统框架 + 辅助功能授权 | 文本与按键注入 |
| 持久化 | SwiftData | App target | Profile 与 Take 本地存储 |
| 音频回放 | AVFoundation + AudioToolbox | 系统框架 | Recorder 回放与 CLI 渲染 |

## 第一方模块 / 包

| 模块 / 包 | 位置 | 产物 | 被谁依赖 |
| --- | --- | --- | --- |
| `PianoKey` | `PianoKey/` + Xcode target | `PianoKey.app` | 终端用户 |
| `MenuBarDockKit` | `Packages/MenuBarDockKit/` | Swift library | `PianoKey` target |
| `PianoKeyCLI` | `Packages/PianoKeyCLI/` | `pianokey-cli` executable | 脚本、AI 流水线、手工终端 |

## 第三方库 / 框架

> 当前仓库未引入外部第三方包，主要依赖 Apple 官方系统框架。

| 依赖 | 类型 | 版本 | 用途 | 风险 / 注意事项 |
| --- | --- | --- | --- | --- |
| CoreMIDI | runtime | 系统内置 | 接收 MIDI 源事件 | 无源或连接失败会导致监听空转 |
| AVFoundation | runtime | 系统内置 | 音频引擎与 sampler | 音色库缺失会导致回放失败 |
| SwiftData | runtime | 系统内置 | 本地模型持久化 | schema 演进需迁移策略 |
| AppKit | runtime | 系统内置 | 激活策略、窗口与菜单栏行为 | 菜单栏/Dock 模式切换需谨慎 |

## 外部服务与平台

| 服务 / 平台 | 调用方 | 协议 / 接口 | 用途 |
| --- | --- | --- | --- |
| macOS Accessibility | `AccessibilityPermissionService` | AX API + CG 请求接口 | 获取事件注入权限 |
| macOS Shortcuts | `ShortcutExecutionService` | `shortcuts://run-shortcut?name=` URL Scheme | 执行用户已有快捷指令 |
| 系统音色库 DLS/SF2 | `AVSamplerMIDIPlaybackService`, `PianoMIDIRenderer` | 文件路径加载 | Acoustic Grand Piano 音色 |

## 构建、测试与开发工具

| 工具 / 命令 | 位置 | 用途 | 备注 |
| --- | --- | --- | --- |
| `open PianoKey.xcodeproj` | 仓库根目录 | 打开主工程 | 主 App 开发入口 |
| `xcodebuild -project ... -scheme PianoKey ... build` | 仓库根目录 | App 构建 | AGENTS 中推荐 |
| `swift build --package-path Packages/PianoKeyCLI` | 仓库根目录 | 构建 CLI | 独立于 Xcode target |
| `swift run --package-path Packages/PianoKeyCLI ...` | 仓库根目录 | 执行 MIDI 渲染 | 支持 `--json` |

## 平台兼容性

- `MenuBarDockKit` 与 `PianoKeyCLI` package manifest 标注 `macOS(.v14)`。
- Xcode 工程 `PianoKey` target 在 `project.pbxproj` 中声明 `MACOSX_DEPLOYMENT_TARGET = 26.0`。
- 仓库是 **macOS-only**；Linux 环境无法执行完整 `xcodebuild` 与 GUI 运行验证。

## 版本与锁定策略

| 维度 | 真值来源 | 当前值 | 备注 |
| --- | --- | --- | --- |
| 分支 | Git | `crh` | 生成时当前分支 |
| Commit | Git | `228d32deee961c17dc0a7c561f90e7753182e805` | 生成时 HEAD |
| App `MARKETING_VERSION` | `configuration.md`（引用 `project.pbxproj`） | 见配置页单一事实源 | 避免多页写死版本值 |
| App `CURRENT_PROJECT_VERSION` | `configuration.md`（引用 `project.pbxproj`） | 见配置页单一事实源 | 避免多页写死版本值 |

## 升级热点与风险

1. 调整部署目标或 Swift 版本时，需同步验证本地包与主工程兼容。
2. 变更音频渲染链路需同时覆盖 App 回放与 CLI 渲染。
3. 若引入第三方包，需新增锁定策略与许可审计流程。

## 示例片段

```swift
// Packages/MenuBarDockKit/Package.swift
let package = Package(
    name: "MenuBarDockKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MenuBarDockKit", targets: ["MenuBarDockKit"])]
)
```

```swift
// Packages/PianoKeyCLI/Package.swift
let package = Package(
    name: "PianoKeyCLI",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "pianokey-cli", targets: ["PianoKeyCLI"])]
)
```

## Coverage Gaps（如有）

- 未发现第三方依赖清单或 SCA 流程说明（当前无第三方包）。
- 未发现自动化版本发布策略（tag/release workflow）。

## 来源引用（Source References）

- `PianoKey.xcodeproj/project.pbxproj`
- `Packages/MenuBarDockKit/Package.swift`
- `Packages/PianoKeyCLI/Package.swift`
- `Packages/PianoKeyCLI/Sources/PianoKeyCLI/main.swift`
- `PianoKey/PianoKeyApp.swift`
- `PianoKey/Services/System/AccessibilityPermissionService.swift`
- `PianoKey/Services/System/ShortcutExecutionService.swift`
- `PianoKey/Services/Playback/AVSamplerMIDIPlaybackService.swift`
- `README.md`
- `AGENTS.md`
