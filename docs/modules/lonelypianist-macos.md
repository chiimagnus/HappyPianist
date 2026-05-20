# Module: LonelyPianist macOS

`LonelyPianist/` 是 macOS MIDI recorder。当前功能边界是监听、录制、导入与回放；它不包含 MIDI mapping、键盘注入或 Dialogue client。

## 入口

| 入口 | 说明 |
| --- | --- |
| `LonelyPianist/LonelyPianistApp.swift` | 创建 SwiftData container、MIDI services、playback services 与 `LonelyPianistViewModel`。 |
| `LonelyPianist/ContentView.swift` | `MainWindowView`，承载 recorder panel。 |
| `LonelyPianist/Views/Recording/RecorderPanelView.swift` | 录制、导入、take 列表、回放输出与 piano roll UI。 |
| `LonelyPianist/ViewModels/LonelyPianistViewModel.swift` | 状态编排与用户命令。 |

## 主要服务

| 服务 | 作用 |
| --- | --- |
| `CoreMIDIInputService` | 监听 MIDI source，解析 MIDI 1.0/2.0 note/control 事件。 |
| `CoreMIDIOutputService` | 枚举外部 destination 并发送 MIDI。 |
| `DefaultRecordingService` | 把 MIDI note events 聚合成 `RecordingTake`。 |
| `SwiftDataRecordingTakeRepository` | 持久化 take。 |
| `RoutedMIDIPlaybackService` | 在内建 sampler 与 CoreMIDI output 间路由回放。 |
| `MIDIFileImporter` | 导入 `.mid` / `.midi` 并转换成 take。 |
| `BluetoothMIDIViewModel` | 打开系统 Bluetooth MIDI 面板并做权限 preflight。 |

## 状态模型

`LonelyPianistViewModel` 管理以下用户可见状态：

- MIDI 监听状态与连接 source 名称。
- 当前 recorder mode：idle、recording、playing。
- take 列表、选中 take、重命名和删除。
- playhead、pressed notes、日志列表。
- 回放输出与当前选中 output。
- Bluetooth MIDI 面板状态。

## 数据和权限

- SwiftData schema：`RecordingTakeEntity`、`RecordedNoteEntity`。
- store：`LonelyPianist.store`。
- entitlements：sandbox、Bluetooth、network client、user-selected read-only files。
- Info.plist：Bluetooth usage description 与 MIDI 文件导入声明。

## 验证

```bash
xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianist -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## 明确不存在

以下路径和类型不在当前代码中，文档或新代码不要引用：

- `Services/Mapping/`
- `Services/Dialogue/`
- `DefaultMappingEngine`
- `DialogueManager`
- keyboard injection / CGEvent mapping 流程
