# 架构

## 系统上下文

LonelyPianist 运行于 macOS 桌面环境，依赖系统框架实现：

- CoreMIDI：采集 MIDI 输入。
- ApplicationServices/CoreGraphics：辅助功能与事件注入。
- AVFoundation/AudioToolbox：Recorder 回放。
- SwiftData：Profile 与 Take 持久化。

系统没有服务端组件，属于 **本地单进程应用** 架构。

## 运行时边界

| 运行单元 | 位置 | 生命周期 | 主要职责 |
| --- | --- | --- | --- |
| LonelyPianist App 进程 | `LonelyPianist/` | App 启动到退出 | UI、监听、映射、录制回放、持久化 |
| MenuBarDockKit 组件 | `Packages/MenuBarDockKit` | 随 App 进程 | 菜单栏/Dock 显示策略与主窗口辅助 |

## 组件地图

| 组件 | 位置 | 输入 | 输出 | 依赖 |
| --- | --- | --- | --- | --- |
| `LonelyPianistViewModel` | `LonelyPianist/ViewModels/LonelyPianistViewModel.swift` | UI 事件 + MIDI 事件 + 仓储数据 | UI 状态 + 动作执行 | 各类 Service Protocol |
| `CoreMIDIInputService` | `LonelyPianist/Services/MIDI` | 系统 MIDI 消息 | `MIDIEvent` 回调 | CoreMIDI |
| `DefaultMappingEngine` | `LonelyPianist/Services/Mapping` | `MIDIEvent` + `MappingProfile` | `ResolvedMappingAction[]` | Mapping models |
| `KeyboardEventService` | `LonelyPianist/Services/Input` | 文本/按键动作 | 系统输入注入 | CGEvent |
| `DefaultRecordingService` | `LonelyPianist/Services/Recording` | note on/off 事件 | `RecordingTake` | `ClockProtocol` |
| `RoutedMIDIPlaybackService` | `LonelyPianist/Services/Playback` | `RecordingTake` | 本机音频或外设 MIDI 输出 + 完成回调 | AVAudioEngine / CoreMIDI |
| SwiftData Repositories | `LonelyPianist/Services/Storage` | Profile/Take domain model | SwiftData entities | SwiftData |

## 依赖方向与层次

- View -> ViewModel -> Protocol -> Service Implementation。
- `LonelyPianistApp` 负责集中注入实现，ViewModel 仅依赖协议。
- Model 层不依赖 UI 框架；Service 层不依赖具体 View。
- 禁止在 View 中直接访问 SwiftData 仓储。

## 关键流程

1. **实时映射链路**：CoreMIDI 事件 -> ViewModel -> MappingEngine -> Keyboard/Shortcut Service。
2. **Recorder 链路**：录制时先写 `DefaultRecordingService`，停止后落盘 `SwiftDataRecordingTakeRepository`；播放时从 Take 生成调度事件驱动 `AVAudioUnitSampler`。

## 图表

```mermaid
flowchart LR
  A[CoreMIDIInputService] --> B[LonelyPianistViewModel]
  B --> C[DefaultMappingEngine]
  C --> D[KeyboardEventService]
  C --> E[ShortcutExecutionService]
  B --> F[DefaultRecordingService]
  F --> G[SwiftDataRecordingTakeRepository]
  B --> H[SwiftDataMappingProfileRepository]
  B --> I[RoutedMIDIPlaybackService]
  J[SwiftUI Views] --> B
  K[MenuBarDockKit] --> J
```

## 接口与契约

| 契约 | 位置 | 调用方 | 含义 |
| --- | --- | --- | --- |
| `MIDIInputServiceProtocol` | `LonelyPianist/Services/Protocols/MIDIInputServiceProtocol.swift` | ViewModel | 启停监听与事件回调契约 |
| `MappingEngineProtocol` | `LonelyPianist/Services/Protocols/MappingEngineProtocol.swift` | ViewModel | 事件匹配输出统一接口 |
| `RecordingServiceProtocol` | `LonelyPianist/Services/Protocols/RecordingServiceProtocol.swift` | ViewModel | 录制状态机契约 |
| `MIDIPlaybackServiceProtocol` | `LonelyPianist/Services/Protocols/MIDIPlaybackServiceProtocol.swift` | ViewModel | 回放/停止与完成通知契约 |
| `RoutableMIDIPlaybackServiceProtocol` | `LonelyPianist/Services/Protocols/RoutableMIDIPlaybackServiceProtocol.swift` | ViewModel | 回放输出选择（Built-in Sampler / 外设 MIDI） |
| `MappingProfileRepositoryProtocol` | `LonelyPianist/Services/Protocols/MappingProfileRepositoryProtocol.swift` | ViewModel | Profile 持久化接口 |
| `RecordingTakeRepositoryProtocol` | `LonelyPianist/Services/Protocols/RecordingTakeRepositoryProtocol.swift` | ViewModel | Take 持久化接口 |

## 状态、存储与消息

- 内存状态：`LonelyPianistViewModel` 管理连接状态、事件计数、当前 Profile、当前 Take、playhead、recent logs。
- 持久化状态：`MappingProfileEntity` + `RecordingTakeEntity` + `RecordedNoteEntity`。
- 消息边界：Service 通过 callback 将事件推回 ViewModel（例如 `onEvent`, `onPlaybackFinished`）。

## 错误处理与可靠性

- MIDI 连接失败通过 `MIDIInputConnectionState.failed` 传播。
- 权限未授权不会直接崩溃，而是显示状态并引导设置页。
- 回放失败、seek 失败、仓储失败都通过状态文案与 Recent Events 暴露。
- 旋律触发设置冷却窗口，降低重复触发抖动风险。

## 部署 / 发布拓扑

- App：Xcode target `LonelyPianist`（`com.chiimagnus.LonelyPianist`）。
- 单元测试：Xcode target `LonelyPianistTests`。
- 本地包：`MenuBarDockKit` 由 Xcode 工程引用。

## 扩展点与热点

| 扩展点 | 建议入口 | 风险 |
| --- | --- | --- |
| 新映射类型 | `MappingActionType` + `DefaultMappingEngine` + `execute(_:)` | 需要同步 UI 编辑器与解析器 |
| 新录制元数据 | `RecordedNote` / `RecordingTake` + SwiftData entity | 需要迁移策略与仓储联动 |
| 新输入源 | `MIDIInputServiceProtocol` 新实现 | 连接状态、回调时序需一致 |
| 新回放引擎 | `MIDIPlaybackServiceProtocol` 新实现 | playhead、停止语义需兼容 |

## 示例片段

```swift
// LonelyPianist/LonelyPianistApp.swift
viewModel.bootstrap()
AppContext.shared.viewModel = viewModel
_viewModel = State(initialValue: viewModel)
```

```swift
// LonelyPianist/ViewModels/LonelyPianistViewModel.swift
playbackService.onPlaybackFinished = { [weak self] in
    Task { @MainActor [weak self] in
        guard let self else { return }
        if recorderMode == .playing {
            recorderMode = .idle
            recorderStatusMessage = "Playback finished"
        }
    }
}
```

## Coverage Gaps（如有）

- 缺少 CI workflow 证据，无法确认自动化发布/测试拓扑。
- 尚未发现 SwiftData schema 版本迁移策略文档。

## 来源引用（Source References）

- `LonelyPianist/LonelyPianistApp.swift`
- `LonelyPianist/ContentView.swift`
- `LonelyPianist/ViewModels/LonelyPianistViewModel.swift`
- `LonelyPianist/Services/Protocols/MIDIInputServiceProtocol.swift`
- `LonelyPianist/Services/Protocols/MappingEngineProtocol.swift`
- `LonelyPianist/Services/MIDI/CoreMIDIInputService.swift`
- `LonelyPianist/Services/MIDI/CoreMIDIOutputService.swift`
- `LonelyPianist/Services/Mapping/DefaultMappingEngine.swift`
- `LonelyPianist/Services/Playback/RoutedMIDIPlaybackService.swift`
- `LonelyPianist/Services/Playback/AVSamplerMIDIPlaybackService.swift`
- `LonelyPianist/Services/Playback/CoreMIDIOutputMIDIPlaybackService.swift`
- `LonelyPianist/Services/Storage/SwiftDataMappingProfileRepository.swift`
- `LonelyPianist/Services/Storage/SwiftDataRecordingTakeRepository.swift`
- `LonelyPianist.xcodeproj/project.pbxproj`
- `Packages/MenuBarDockKit/Sources/MenuBarDockKit/DockPresenceService.swift`
