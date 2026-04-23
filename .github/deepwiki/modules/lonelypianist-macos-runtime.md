# macOS Runtime

## 范围
Runtime 页处理“连没连上、当前在做什么、按下去后发生了什么”。

## 关键对象
| 对象 | 职责 |
| --- | --- |
| `LonelyPianistViewModel` | 运行面状态总控 |
| `CoreMIDIInputService` | 输入监听与来源刷新 |
| `CoreMIDIOutputService` | 目标 MIDI 目的地枚举与发送 |
| `KeyboardEventService` | CGEvent 按键注入 |
| `ShortcutExecutionService` | 打开 Shortcuts URL scheme |

## 生命周期
1. `LonelyPianistApp` 初始化 `ModelContainer`、输入输出服务和 `DialogueManager`。
2. `bootstrap()` 读取权限、配置和 takes。
3. `startListening()` 打开 CoreMIDI。
4. `refreshMIDISources()` 重新绑定来源。
5. `stopListening()` 清空状态并重置 mapping。

## 状态和可观察字段
| 字段 | 含义 |
| --- | --- |
| `connectionState` | MIDI 连接状态 |
| `connectedSourceNames` | 当前来源名 |
| `midiEventCount` | 事件计数 |
| `pressedNotes` | 当前按下集合 |
| `recentLogs` | 最近日志 |
| `statusMessage` | 顶层状态提示 |

## 调试抓手
- 无输出：先看 `hasAccessibilityPermission`。
- 无来源：先看 `connectionState` 和 `connectedSourceNames`。
- 无按键注入：先看 `KeyboardEventService` 是否成功发 CGEvent。


## Coverage Gaps
- 运行面没有自动化系统测试，设备 / 权限问题仍主要靠手工复现。

