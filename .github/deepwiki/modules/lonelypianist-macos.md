# 模块：LonelyPianist macOS

## 边界
- 负责：MIDI 监听、映射编辑与执行、录音 / 回放、Dialogue 会话控制。
- 不负责：visionOS 追踪和 Python 推理细节。

## 目录地图
| 路径 | 角色 |
| --- | --- |
| `ViewModels/` | 业务编排 |
| `Services/MIDI/` | MIDI 输入 / 输出 |
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
- [Runtime](modules/lonelypianist-macos-runtime.md)
- [Mappings](modules/lonelypianist-macos-mapping.md)
- [Recorder](modules/lonelypianist-macos-recording.md)
- [Dialogue](modules/lonelypianist-macos-dialogue.md)

## 风险点
- `handleMIDIEvent`
- `setSingleKeyMapping`
- `stopTransport`
- `DialogueManager.start()`


## Coverage Gaps
- 集成测试仍主要覆盖 service / view model 层，没有系统级 E2E。

