# macOS Runtime

## 范围
Runtime 页处理“连没连上、当前在做什么、按下去后发生了什么”。

## 关键对象
| 对象 | 职责 |
| --- | --- |
| `LonelyPianistViewModel` | 运行面状态总控 |
| `CoreMIDIInputService` | 输入监听与来源刷新 |
| `CoreMIDIOutputService` | 目标 MIDI 目的地枚举与发送 |
| `BluetoothAccessPreflight` | 在打开系统 `Bluetooth MIDI…` 连接窗口前预检蓝牙权限/开关，提供面向用户的引导提示 |
| `KeyboardEventService` | CGEvent 按键注入 |
| `ShortcutExecutionService` | 打开 Shortcuts URL scheme |

## 生命周期
1. `LonelyPianistApp` 初始化 `ModelContainer`、输入输出服务和 `DialogueManager`。
2. `bootstrap()` 读取权限、配置和 takes。
3. `startListening()` 打开 CoreMIDI。
4. `refreshMIDISources()` 重新绑定来源。
5. `stopListening()` 清空状态并重置 mapping。

蓝牙 MIDI（BLE MIDI）连接路径：

1. 用户点击工具栏 `Bluetooth MIDI…`（`RecorderPanelView`）。
2. `BluetoothAccessPreflight` 使用 CoreBluetooth 判断：
   - 权限是否被拒绝（提示去 System Settings 打开）
   - 系统蓝牙是否关闭（提示去打开蓝牙）
3. 通过预检后，打开系统 `CABTLEMIDIWindowController` 让用户完成 Connect。
4. 连接完成后，BLE MIDI 以 CoreMIDI source 形式出现，`CoreMIDIInputService` 会在系统 setup 变更通知后自动 refresh sources。

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
- BLE MIDI 连接失败：先确认蓝牙权限与蓝牙开关，再确认设备是否已在系统窗口中 Connected。
- 无按键注入：先看 `KeyboardEventService` 是否成功发 CGEvent。


## Coverage Gaps
- 运行面没有自动化系统测试，设备 / 权限问题仍主要靠手工复现。

## 更新记录（Update Notes）
- 2026-05-12: 同步 BLE MIDI 连接入口迁移为 App 内 `Bluetooth MIDI…`，以及蓝牙权限/开关的预检与引导。
