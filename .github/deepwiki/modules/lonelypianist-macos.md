# 模块：LonelyPianist macOS

## 边界
- 负责：MIDI 监听、映射编辑与执行、录音 / 回放、Dialogue 会话控制。
- 不负责：visionOS 追踪和 Python 推理细节。

## 目录地图
| 路径 | 角色 |
| --- | --- |
| `ViewModels/` | 业务编排 |
| `Services/MIDI/` | MIDI 输入 / 输出 |
| `Services/Bluetooth/` | BLE MIDI 连接前置检查（权限/开关），用于在 App 内打开系统 Bluetooth MIDI 连接窗口 |
| `Services/Mapping/` | mapping engine |
| `Services/Dialogue/` | turn-based 对话 |
| `Services/Recording/` | take 构建 |
| `Services/Storage/` | SwiftData 持久化 |
| `Views/` | UI |

## 入口与生命周期
| 入口 | 行为 |
| --- | --- |
| `LonelyPianistApp.swift` | 组装容器、服务、view model |
| `bootstrap()` | 读权限、seed config、加载 takes、刷新输出 |
| `toggleListening()` | 启停 CoreMIDI |
| `startDialogue()` | 打开 WS + silence loop |
| `startRecordingTake()` / `playSelectedTake()` | Recorder 录放 |

## 重要子页
- [Runtime](lonelypianist-macos-runtime.md)
- [Mappings](lonelypianist-macos-mapping.md)
- [Recorder](lonelypianist-macos-recording.md)
- [Dialogue](lonelypianist-macos-dialogue.md)

## 风险点
- `handleMIDIEvent`
- `setSingleKeyMapping`
- `stopTransport`
- `DialogueManager.start()`
- `RecorderPanelView.openBluetoothMIDIWindow()`（蓝牙权限/系统窗口行为受环境影响）


## Coverage Gaps
- 集成测试仍主要覆盖 service / view model 层，没有系统级 E2E。

## 更新记录（Update Notes）
- 2026-04-26: 修复模块页内部链接（从 `modules/` 前缀改为同目录相对路径）。
- 2026-05-12: 同步 macOS BLE MIDI 连接入口迁移为 App 内 `Bluetooth MIDI…`（系统窗口 + 权限预检）。
