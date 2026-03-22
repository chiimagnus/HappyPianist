# 术语表

## 说明

本页统一 PianoKey 仓库中的业务词汇、工程词汇与运行词汇，避免不同页面对同一概念使用不同称呼。

## 业务术语

| 术语 | 定义 | 常见位置 | 为什么重要 |
| --- | --- | --- | --- |
| Profile | 一组可切换映射配置 | Mappings 页、Repository | 规则组织与场景切换核心单元 |
| Single Key Rule | 单音符 -> 文本输出规则 | `MappingRule.swift` | 最基础映射能力 |
| Chord Rule | 同时按下多个音符 -> 动作 | `MappingRule.swift` | 快捷触发复杂操作 |
| Melody Rule | 音符序列 + 时间窗口 -> 动作 | `MappingRule.swift` | 序列语义触发 |
| Take | 一次录制得到的音符集合 | Recorder 页、`RecordingTake` | Recorder 核心产物 |

## 架构 / 工程术语

| 术语 | 定义 | 常见位置 | 为什么重要 |
| --- | --- | --- | --- |
| Mapping Engine | 负责把 MIDIEvent 匹配为动作的核心引擎 | `DefaultMappingEngine.swift` | 行为正确性的中心 |
| Service Protocol | ViewModel 依赖的抽象接口 | `Services/Protocols/*` | 可测试与可替换实现基础 |
| Connection State | MIDI 输入连接状态机 | `MIDIInputServiceProtocol.swift` | 运行可观测性第一信号 |
| Playhead | 回放时间轴指针 | Recorder UI + ViewModel | Seek/播放进度控制 |
| Dock Visibility Controller | 主窗口与 Dock 显示策略协调器 | `MainWindowDockVisibilityController.swift` | 菜单栏工具壳体验关键 |

## 运行 / 发布术语

| 术语 | 定义 | 常见位置 | 为什么重要 |
| --- | --- | --- | --- |
| Accessibility Permission | macOS 辅助功能授权 | Runtime 状态、权限服务 | 决定是否可注入系统输入 |
| Source Refresh | 重连 MIDI 来源动作 | Runtime/MenuBar 按钮 | 常见故障恢复入口 |
| Marketing Version | 展示版本号 | `project.pbxproj` | 发布沟通与版本追踪 |

## 易混淆概念

- **Listening MIDI** vs **可跨应用输入**：前者只表示已进入监听，后者还要求辅助功能授权。
- **Recorder 回放** vs **映射注入**：回放仅发声，不触发文本/按键/快捷指令注入。
- **MenuBarOnly 模式隐藏 Dock** vs **应用退出**：窗口关闭后可隐藏 Dock，但应用仍在菜单栏存活。

## Coverage Gaps（如有）

- 尚无正式术语词典自动校验机制（目前靠人工维护一致性）。

## 来源引用（Source References）

- `README.md`
- `PianoKey/Models/Mapping/MappingRule.swift`
- `PianoKey/Models/Mapping/MappingAction.swift`
- `PianoKey/Models/Recording/RecordingTake.swift`
- `PianoKey/ViewModels/PianoKeyViewModel.swift`
- `PianoKey/Services/Mapping/DefaultMappingEngine.swift`
- `PianoKey/Services/Protocols/MIDIInputServiceProtocol.swift`
- `Packages/MenuBarDockKit/Sources/MenuBarDockKit/MainWindowDockVisibilityController.swift`
