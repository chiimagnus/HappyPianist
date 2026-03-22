# 概览

## 仓库目标与用户

PianoKey 仓库主要包含两条运行面：

1. `PianoKey` 主应用（macOS 菜单栏 App，实时 MIDI -> 系统输入 + Recorder）。
2. `Packages/MenuBarDockKit`（抽象菜单栏应用的 Dock 可见性与窗口桥接能力）。

仓库当前聚焦主应用与共享包，不再保留独立命令行运行面。

用户包括终端用户（PianoKey App）和开发者（模块维护）。

## 一句话心智模型

- PianoKey 主应用在启动时完成依赖注入并启动状态机。
- CoreMIDI 输入进入 `PianoKeyViewModel`，先更新运行状态，再进入映射引擎与 Recorder 分支。
- 映射命中后触发文本/组合键/快捷指令；Recorder 分支把事件序列化为 Take 并可回放。
- 所有配置与录制资产持久化在 SwiftData 实体中。

## 产品线 / 运行面

| 运行面 | 位置 | 作用 | 主要入口 |
| --- | --- | --- | --- |
| PianoKey App | `PianoKey/` | 实时 MIDI 映射、权限管理、Recorder UI | `PianoKey/PianoKeyApp.swift` |
| MenuBarDockKit | `Packages/MenuBarDockKit/` | 菜单栏/Dock 显示策略与 `NSWindow` 读取 | `AppIconDisplayMode.swift`, `DockPresenceService.swift` |

## 仓库布局

| 路径 | 职责 | 为什么重要 |
| --- | --- | --- |
| `PianoKey/Models` | 领域模型 + SwiftData 实体 | 定义规则结构、录制结构与持久化模型 |
| `PianoKey/Services` | MIDI/输入注入/权限/仓储/回放服务 | 业务执行核心与可替换实现点 |
| `PianoKey/ViewModels` | 状态编排与流程入口 | 跨 UI 与服务的单一状态协调层 |
| `PianoKey/Views` | Runtime/Mapping/Recorder/Settings UI | 用户旅程触发入口 |
| `PianoKeyTests` | 录制与状态机测试 | 当前自动化回归基线 |
| `Packages/MenuBarDockKit` | 本地共享包（UI 壳能力） | 主应用窗口行为依赖项 |

## 入口点

| 入口 | 位置 | 用途 | 常用命令 / 调用方式 |
| --- | --- | --- | --- |
| App 主入口 | `PianoKey/PianoKeyApp.swift` | 装配 ModelContainer 与服务依赖 | `open PianoKey.xcodeproj` |
| 菜单栏入口 | `PianoKey/Views/MenuBar/MenuBarMenuContentView.swift` | Start/Stop/Rec/Play/Open 主窗口 | 菜单栏图标操作 |
| 主窗口入口 | `PianoKey/ContentView.swift` | Runtime/Mappings/Recorder/Settings 导航 | `Open PianoKey` 按钮 |

## 关键产物

| 产物 | 生成方 | 去向 | 说明 |
| --- | --- | --- | --- |
| 映射配置（Profile） | `SwiftDataMappingProfileRepository` | 本地 SwiftData | 含单键/和弦/旋律规则与力度阈值 |
| 录制 Take | `DefaultRecordingService` + `SwiftDataRecordingTakeRepository` | 本地 SwiftData | 按更新时间排序，重启后恢复 |
| 回放输出 | `RoutedMIDIPlaybackService` | 本机音频或外设 MIDI | 可选 Built-in Sampler 或外部 MIDI destination |

## 关键工作流

| 工作流 | 触发点 | 步骤摘要 | 结果 |
| --- | --- | --- | --- |
| 首次授权与监听 | 用户点击 Start/Grant | 请求授权 -> 启动 MIDI -> 连接 Source | 可以在前台应用看到输入效果 |
| 规则编辑与验证 | 用户进入 Mappings | 编辑规则 -> 立即弹奏验证 | 输出行为即时变化并持久化 |
| 录制与回放 | 用户点击 Rec/Play | 录制 note on/off -> 保存 Take -> 回放 | 可重复试听录制内容 |

## 示例片段

```swift
// PianoKey/PianoKeyApp.swift
let midiOutputService = CoreMIDIOutputService()
let playbackService = RoutedMIDIPlaybackService(
    samplerPlayback: AVSamplerMIDIPlaybackService(),
    midiOutPlayback: CoreMIDIOutputMIDIPlaybackService(outputService: midiOutputService),
    outputService: midiOutputService
)
let viewModel = PianoKeyViewModel(
    midiInputService: CoreMIDIInputService(),
    keyboardEventService: KeyboardEventService(),
    permissionService: AccessibilityPermissionService(),
    repository: repository,
    recordingRepository: recordingRepository,
    recordingService: DefaultRecordingService(clock: SystemClock()),
    playbackService: playbackService,
    mappingEngine: DefaultMappingEngine(),
    shortcutService: ShortcutExecutionService()
)
```

```bash
# 主工程构建命令
xcodebuild -project PianoKey.xcodeproj -scheme PianoKey -configuration Debug build
```

## 从哪里开始

1. 业务优先：先读 [business-context.md](business-context.md)。
2. 工程优先：直接读 [architecture.md](architecture.md) + [data-flow.md](data-flow.md)。
3. 改具体能力时跳到 `modules/*` 对应页面。

## 如何导航

- `INDEX.md` 提供 `business-first` 与 `engineering-first` 两条阅读路径。
- `troubleshooting.md` 用于“症状 -> 定位 -> 处理”。
- `configuration.md` 与 `storage.md` 负责“默认值、持久化、漂移风险”。

## 常见陷阱

- 看到 `Listening MIDI` 不代表已具备跨应用注入能力；仍需辅助功能授权。
- 回放成功不等于映射链路成功；回放与注入链路是隔离的。

## Coverage Gaps（如有）

- 当前仓库未发现 `.github/workflows/`，CI 门禁规则依赖人工流程。
- 未见自动化发布脚本或签名/公证流水线定义。

## 来源引用（Source References）

- `README.md`
- `AGENTS.md`
- `PianoKey/PianoKeyApp.swift`
- `PianoKey/ContentView.swift`
- `PianoKey/ViewModels/PianoKeyViewModel.swift`
- `PianoKey/Services/MIDI/CoreMIDIOutputService.swift`
- `PianoKey/Services/Playback/RoutedMIDIPlaybackService.swift`
- `PianoKey/Services/Storage/SwiftDataMappingProfileRepository.swift`
- `PianoKey/Services/Storage/SwiftDataRecordingTakeRepository.swift`
- `Packages/MenuBarDockKit/Package.swift`
- `PianoKey.xcodeproj/project.pbxproj`
