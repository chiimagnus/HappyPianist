# 模块：LonelyPianist macOS

## 职责与边界
- **负责**：MIDI 监听与来源管理、键位映射编辑与执行、录音/回放、Dialogue 会话控制。
- **不负责**：模型推理细节、visionOS AR 渲染与手部追踪。
- **位置**：`LonelyPianist/`，由 `LonelyPianistApp` 初始化依赖并注入 `LonelyPianistViewModel`。

## 目录范围
| 路径 | 角色 | 备注 |
| --- | --- | --- |
| `LonelyPianist/ViewModels/` | 状态与业务编排 | `@Observable` ViewModel |
| `LonelyPianist/Services/MIDI/` | 输入输出 MIDI 服务 | CoreMIDI 适配 |
| `LonelyPianist/Services/Mapping/` | 映射规则执行 | single/chord/velocity |
| `LonelyPianist/Services/Dialogue/` | 对话状态机与 WS 客户端 | turn-based 交互 |
| `LonelyPianist/Services/Recording/` | 录音构建 | NoteOn/Off 合并 |
| `LonelyPianist/Services/Playback/` | 内建采样器或 MIDI 输出回放 | 路由可切换 |
| `LonelyPianist/Services/Storage/` | SwiftData 持久化 | 映射配置 + take |
| `LonelyPianist/Views/` | Runtime/Mapping/Recorder/Dialogue UI | 仅展示与交互绑定 |

## 入口点与生命周期
| 入口 / 类型 | 位置 | 何时触发 | 结果 |
| --- | --- | --- | --- |
| App 启动 | `LonelyPianistApp.swift` | 进程启动 | 初始化容器、服务、ViewModel，执行 `bootstrap()` |
| Runtime Start | `StatusSectionView` -> `toggleListening()` | 用户点击 Start | 启动 MIDI 输入并更新连接状态 |
| Dialogue Start | `DialogueControlView` -> `startDialogue()` | 用户点击 Start Dialogue | 进入 listening->thinking->playing 状态循环 |
| Recorder 录音/回放 | `RecorderPanelView` | 用户操作 transport | 生成/播放 take |

## 关键文件
| 文件 | 用途 | 为什么值得看 |
| --- | --- | --- |
| `LonelyPianistApp.swift` | 依赖组装与默认配置 | 这里决定运行时拓扑 |
| `ViewModels/LonelyPianistViewModel.swift` | 业务总编排 | 多能力汇聚点、改动影响面最大 |
| `Services/MIDI/CoreMIDIInputService.swift` | MIDI 事件采集与归一化 | 事件入口与稳定性关键 |
| `Services/Mapping/DefaultMappingEngine.swift` | single/chord 规则解析 | 直接决定映射触发语义 |
| `Services/Dialogue/DialogueManager.swift` | 对话状态机 | 跨服务协同核心 |
| `Services/Storage/SwiftDataRecordingTakeRepository.swift` | take 持久化 | Recorder/Dialogue 共用存储层 |
| `Views/Mapping/PianoMappingsEditorView.swift` | 规则编辑 UI | 绑定交互复杂度最高 |

## 上下游依赖
| 方向 | 对象 | 关系 | 影响 |
| --- | --- | --- | --- |
| 下游 | Python 服务 | WS `generate` | 服务不可用会影响 Dialogue |
| 下游 | CoreMIDI / CGEvent / AVFoundation | 系统能力调用 | 权限/设备异常会阻断核心能力 |
| 上游 | 用户交互（SwiftUI） | Start/Stop/Bind/Record 操作 | 驱动状态机迁移 |
| 上游 | 持久化数据（SwiftData） | 配置与 take 恢复 | 影响启动后的可用状态 |

## 对外接口与契约
| 接口 / 命令 / 类型 | 位置 | 调用方 | 含义 |
| --- | --- | --- | --- |
| `MIDIInputServiceProtocol` | `Services/Protocols` | ViewModel | 监听与来源刷新 |
| `RoutableMIDIPlaybackServiceProtocol` | `Services/Protocols` | ViewModel / DialogueManager | 统一回放能力 |
| `DialogueServiceProtocol` | `Services/Protocols` | DialogueManager | WS 请求/响应抽象 |
| `RecordingTakeRepositoryProtocol` | `Services/Protocols` | Recorder + Dialogue | take 读写与重命名删除 |

## 数据契约、状态与存储
- 关键模型：
  - `MIDIEvent`
  - `MappingConfigPayload`
  - `RecordingTake` / `RecordedNote`
  - `DialogueNote` / `DialogueGenerateParams`
- 关键状态：
  - `isListening`
  - `recorderMode`
  - `dialogueStatus`
  - `selectedPlaybackOutputID`
- 持久化：
  - SwiftData store 管理映射配置与 takes；
  - Dialogue 会话也以 `RecordingTake` 形式落库。

## 配置与功能开关
- `DialoguePlaybackInterruptionBehavior` 持久化在 `UserDefaults`，默认 `interrupt`。
- 映射层支持 `velocityEnabled` 与阈值配置。

## 正常路径与边界情况
- 正常路径：MIDI -> 状态更新 ->（映射或录音或对话）-> UI 反馈与持久化。
- 边界情况：
  - 权限缺失：直接阻断 Start Listening 并提示。
  - 播放中切换输出：先 stop 再切换，避免状态错乱。
  - Dialogue thinking 期间输入：当前策略为忽略，避免并发状态复杂化。

## 扩展点与修改热点
- 扩展点：
  - 新增映射触发类型（需扩展 MappingEngine + UI 编辑器）。
  - 新增 Dialogue 参数或策略（需同步 Swift/Python 协议）。
  - 新增回放后端（扩展 Routable playback）。
- 修改热点：
  - `handleMIDIEvent`、`startDialogue/stopDialogue`、`stopTransport`。
  - `PianoMappingsEditorView`（多种编辑模式耦合）。

## 测试与调试
- 相关测试：
  - `LonelyPianistTests/Mapping/UnifiedMappingConfigTests.swift`
  - `LonelyPianistTests/Recording/DefaultRecordingServiceTests.swift`
  - `LonelyPianistTests/SilenceDetectionServiceTests.swift`
  - `LonelyPianistTests/ViewModels/LonelyPianistViewModelRecorderStateTests.swift`
- 调试抓手：
  - Runtime Recent Events
  - `statusMessage` / `recorderStatusMessage`
  - Python `health` 与 WS test client

## 示例片段
```swift
// 映射动作执行
let resolvedActions = mappingEngine.process(event: event, payload: activeConfig.payload)
for resolvedAction in resolvedActions {
    try execute(resolvedAction.keyStroke)
}
```

```swift
// Dialogue 开始时绑定会话与静默检测
silenceDetectionService.reset()
dialogueService.connect(url: serverURL)
status = .listening
startPolling()
```

## Coverage Gaps
- 未见针对 `CoreMIDIInputService` 的集成测试（主要依赖运行时验证）。
