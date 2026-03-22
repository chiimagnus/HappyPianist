# 集成：macOS 系统接口

## 集成范围概览

| 接口 | 调用模块 | 用途 | 失败表现 |
| --- | --- | --- | --- |
| CoreMIDI | `CoreMIDIInputService` | 接收 MIDI 事件 | 无事件 / 连接失败 |
| CoreMIDI（输出验证脚本） | `.github/scripts/midi-send-test.swift` | 验证 macOS → 外部设备的 MIDI 输出链路 | 找不到 destination / send 失败 |
| Accessibility API | `AccessibilityPermissionService` | 检查与请求注入权限 | 无法跨应用输入 |
| CGEvent | `KeyboardEventService` | 发送文本与组合键 | 动作执行失败 |
| Shortcuts URL Scheme | `ShortcutExecutionService` | 触发系统快捷指令 | open 失败 |
| AVAudioEngine/AVAudioUnitSampler | `AVSamplerMIDIPlaybackService` + CLI renderer | 播放与离线渲染 | 回放/渲染失败 |

## CoreMIDI 集成细节

- 使用 `MIDIClientCreate` + `MIDIInputPortCreateWithProtocol` 建立输入端口。
- 通过 `MIDIEventListForEachEvent` 遍历消息，仅保留 note on/off。
- Source 刷新时对全部 source 尝试连接。
- 仓库内提供一个“输出链路验证”脚本：`swift .github/scripts/midi-send-test.swift --list`（列出 destinations）与 `swift .github/scripts/midi-send-test.swift --dest <index>`（发送 Note On/Off）。

## 权限与输入注入集成

- 权限检测：`AXIsProcessTrusted()` + `CGPreflightPostEventAccess()`。
- 权限请求：`AXIsProcessTrustedWithOptions` + `CGRequestPostEventAccess()`。
- 注入动作：`CGEvent` keyboard event 或 Unicode string post。

## 快捷指令集成

- 通过 `shortcuts://run-shortcut?name=<encoded>` 调起系统 Shortcuts。
- 空名称或编码失败会抛 `ShortcutServiceError.invalidName`。

## 音频与音色库集成

- 默认尝试系统音色库路径：
  - `gs_instruments.dls`
  - `DefaultBankGS.sf2`
- 找不到时抛出 `soundBankNotFound`。

## 示例片段

```swift
// CoreMIDIInputService.swift
let status = MIDIInputPortCreateWithProtocol(
    clientRef,
    "PianoKeyMIDIInput" as CFString,
    MIDIProtocolID._1_0,
    &inputPortRef
) { [weak self] eventList, _ in
    self?.handleEventList(eventList)
}
```

```swift
// KeyboardEventService.swift
keyDown.post(tap: .cghidEventTap)
keyUp.post(tap: .cghidEventTap)
```

## 常见集成故障与排查

| 故障 | 首查点 | 处理思路 |
| --- | --- | --- |
| 无 MIDI 输入 | Source 数量与连接状态 | Refresh Sources，确认设备在线 |
| 有 MIDI 无注入 | 权限状态 | 补齐辅助功能授权 |
| shortcut 不执行 | URL 生成与 open 返回值 | 校验名称与系统快捷指令存在性 |
| 回放失败 | 音色库路径与引擎状态 | 指定 `--sound-bank` 或检查系统环境 |

## Coverage Gaps（如有）

- 目前未见统一接口健康检查工具，排查依赖运行时状态文案。

## 来源引用（Source References）

- `PianoKey/Services/MIDI/CoreMIDIInputService.swift`
- `PianoKey/Services/System/AccessibilityPermissionService.swift`
- `PianoKey/Services/Input/KeyboardEventService.swift`
- `PianoKey/Services/System/ShortcutExecutionService.swift`
- `PianoKey/Services/Playback/AVSamplerMIDIPlaybackService.swift`
- `Packages/PianoKeyCLI/Sources/PianoKeyCLI/main.swift`
- `PianoKey/ViewModels/PianoKeyViewModel.swift`
- `.github/scripts/midi-send-test.swift`
