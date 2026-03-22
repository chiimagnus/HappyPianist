# 模块：PianoKey 主应用

## 职责与边界

- 负责：
  - 启动与依赖注入。
  - Runtime / Mappings / Recorder / Settings UI。
  - MIDI 监听、映射执行、权限管理、录制与回放状态机。
  - Profile 与 Take 的本地持久化。
- 不负责：
  - 在线同步、云端服务、多人协作。
  - 音频工程级编辑（如多轨编辑、效果器链）。

## 目录范围

| 路径 | 角色 | 备注 |
| --- | --- | --- |
| `PianoKey/PianoKeyApp.swift` | App 入口 | 依赖注入与 Scene 组装 |
| `PianoKey/ViewModels/PianoKeyViewModel.swift` | 状态编排核心 | 业务流程主调度器 |
| `PianoKey/Services/*` | 基础能力 | MIDI/映射/输入/权限/回放/存储 |
| `PianoKey/Views/*` | 用户界面 | Runtime/Mapping/Recording/Settings |
| `PianoKey/Models/*` | 领域与存储模型 | Mapping / MIDI / Recording / SwiftData entities |

## 入口点与生命周期

| 入口 / 类型 | 位置 | 何时触发 | 结果 |
| --- | --- | --- | --- |
| `PianoKeyApp.init()` | `PianoKeyApp.swift` | App 启动 | 初始化 ModelContainer + ViewModel |
| `viewModel.bootstrap()` | `PianoKeyViewModel.swift` | 启动后 | 种子 profile、加载 profile/takes |
| `toggleListening()` | `PianoKeyViewModel.swift` | 用户点击 Start/Stop | 启停 MIDI 输入服务 |
| `startRecordingTake()` / `stopTransport()` | `PianoKeyViewModel.swift` | Recorder 操作 | 录制状态切换与持久化 |

## 关键文件

| 文件 | 用途 | 为什么值得看 |
| --- | --- | --- |
| `PianoKey/PianoKeyApp.swift` | 依赖注入与场景定义 | 任何跨服务改动都要看这里 |
| `PianoKey/ViewModels/PianoKeyViewModel.swift` | 主状态机 | 修改行为最核心热点 |
| `PianoKey/Services/MIDI/CoreMIDIInputService.swift` | MIDI 接入 | 输入链路首环 |
| `PianoKey/Services/Mapping/DefaultMappingEngine.swift` | 规则匹配 | 触发逻辑核心 |
| `PianoKey/Services/Playback/AVSamplerMIDIPlaybackService.swift` | 回放实现 | Recorder 可用性关键 |
| `PianoKey/Services/Playback/RoutedMIDIPlaybackService.swift` | 回放路由 | 输出选择（本机/外设） |
| `PianoKey/Views/Mapping/RulesEditorSectionView.swift` | 规则编辑 UI | 用户可配置面主入口 |

## 上下游依赖

| 方向 | 对象 | 关系 | 影响 |
| --- | --- | --- | --- |
| 上游 | 用户 UI 操作 | View 触发 ViewModel 方法 | 决定状态机分支 |
| 上游 | CoreMIDI | 通过 service 回调输入事件 | 触发映射/录制链路 |
| 下游 | Keyboard/Shortcut Service | 执行动作输出 | 影响前台应用输入行为 |
| 下游 | SwiftData Repositories | 保存配置与录制资产 | 影响重启恢复结果 |
| 下游 | Playback Service | 回放 Take | 影响 Recorder 体验 |

## 对外接口与契约

| 接口 / 类型 | 位置 | 调用方 | 含义 |
| --- | --- | --- | --- |
| `PianoKeyViewModel` 公共方法 | `ViewModels/PianoKeyViewModel.swift` | SwiftUI Views | 所有用户交互的命令入口 |
| `MappingProfileRepositoryProtocol` | `Services/Protocols` | ViewModel | Profile CRUD 契约 |
| `RecordingTakeRepositoryProtocol` | `Services/Protocols` | ViewModel | Take CRUD 契约 |
| `MIDIInputServiceProtocol` | `Services/Protocols` | ViewModel | MIDI 生命周期与事件回调 |

## 数据契约、状态与存储

- 关键状态：`isListening`, `connectionState`, `activeProfileID`, `recorderMode`, `selectedTakeID`。
- 关键数据：`MappingProfilePayload`, `RecordingTake`, `RecordedNote`。
- 存储落点：SwiftData `MappingProfileEntity` 与 `RecordingTakeEntity`。

## 配置与功能开关

| 项目 | 位置 | 默认值 | 生效方式 |
| --- | --- | --- | --- |
| App 图标模式 | `AppIconDisplayMode.userDefaultsKey` | 启动注册 `menuBarOnly` | 变更即应用 |
| 力度开关 | `MappingProfilePayload.velocityEnabled` | 取 profile 配置 | 规则实时生效 |
| 力度阈值 | `defaultVelocityThreshold` | `90`（empty payload） | 匹配时读取 |

## 正常路径与边界情况

1. 正常路径：授权 -> 监听 -> 匹配 -> 执行动作 -> 日志反馈。
2. 边界：无 Source 时可处于 listening 但 `sourceCount == 0`。
3. 边界：播放中 seek 会触发异步重启播放。
4. 边界：录制停止时自动闭合未 noteOff 的音符。

## 扩展点与修改热点

- 新动作类型：`MappingActionType` + `execute(_:)` + RulesEditor UI 同步变更。
- 新输入服务：实现 `MIDIInputServiceProtocol` 并在 `PianoKeyApp` 注入。
- 新存储字段：先改 domain model，再改 SwiftData entity + repository。

## 测试与调试

- 重点单测：`PianoKeyViewModelRecorderStateTests`、`DefaultRecordingServiceTests`。
- 调试入口：Runtime `Recent Events`、`statusMessage`、`recorderStatusMessage`。

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

```swift
// PianoKey/ViewModels/PianoKeyViewModel.swift
func startListening() {
    hasAccessibilityPermission = permissionService.hasAccessibilityPermission()
    guard hasAccessibilityPermission else {
        statusMessage = "Accessibility permission is required"
        return
    }
    try? midiInputService.start()
}
```

## Coverage Gaps（如有）

- UI 自动化测试缺失；目前主要靠人工回归。
- 复杂权限异常（企业管控设备）未见专项处理逻辑。

## 来源引用（Source References）

- `PianoKey/PianoKeyApp.swift`
- `PianoKey/ContentView.swift`
- `PianoKey/ViewModels/PianoKeyViewModel.swift`
- `PianoKey/Views/Runtime/StatusSectionView.swift`
- `PianoKey/Views/Mapping/RulesEditorSectionView.swift`
- `PianoKey/Views/Recording/RecorderTransportBarView.swift`
- `PianoKey/Services/MIDI/CoreMIDIInputService.swift`
- `PianoKey/Services/MIDI/CoreMIDIOutputService.swift`
- `PianoKey/Services/Mapping/DefaultMappingEngine.swift`
- `PianoKey/Services/Playback/RoutedMIDIPlaybackService.swift`
- `PianoKey/Services/Playback/CoreMIDIOutputMIDIPlaybackService.swift`
- `PianoKey/Services/Storage/SwiftDataMappingProfileRepository.swift`
- `PianoKey/Services/Storage/SwiftDataRecordingTakeRepository.swift`
