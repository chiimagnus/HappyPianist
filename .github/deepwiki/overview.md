# 概览

## 仓库目标与用户
- **目标**：构建一个跨 macOS / visionOS / Python 的钢琴交互系统，覆盖 MIDI 控制、录制回放、AI 对话与 AR 引导练习。
- **用户**：MIDI 键盘用户、需要映射自动化的创作者、Vision Pro 原型验证开发者。
- **核心场景**：
  1. MIDI 输入映射为系统键盘动作。
  2. 你弹一句，模型回一句（Dialogue）。
  3. 外部准备好的 MusicXML 在 AVP 中做分步引导。

## 一句话心智模型
- 仓库由三条运行面组成：**macOS 前端控制台**、**visionOS 空间引导端**、**本机 Python 智能后端**。
- macOS 负责实时 MIDI 与交互编排；Python 提供推理；visionOS 消费外部准备好的 MusicXML + 手部追踪做空间引导。
- 数据主干以 `MIDIEvent`、`RecordingTake`、`DialogueNote`、`MusicXMLScore/PracticeStep` 四类结构串联。

## 产品线 / 运行面
| 运行面 | 位置 | 作用 | 主要入口 |
| --- | --- | --- | --- |
| macOS App | `LonelyPianist/` | MIDI 监听、映射、录音、Dialogue UI | `LonelyPianist/LonelyPianistApp.swift` |
| visionOS App | `LonelyPianistAVP/` | MusicXML 导入、校准、手部追踪、AR 步骤高亮 | `LonelyPianistAVP/LonelyPianistAVPApp.swift` |
| Python 服务 | `piano_dialogue_server/` | `WS /ws` 对话推理 | `piano_dialogue_server/server/main.py` |

## 仓库布局
| 路径 | 职责 | 为什么重要 |
| --- | --- | --- |
| `LonelyPianist/Models|Services|ViewModels|Views` | macOS 主应用分层（MVVM + Services） | 改交互、业务流程、系统 I/O 都在这里 |
| `LonelyPianistAVP/` | visionOS 原型（导入、校准、手部追踪、RealityKit 叠层） | AR Guide 主逻辑与体验入口 |
| `piano_dialogue_server/server/` | FastAPI + WebSocket 协议与推理接线 | Dialogue 服务契约与行为边界 |
| `LonelyPianistTests/` | macOS Swift Testing 单测 | 保障映射、录制、静默检测与 ViewModel 状态机 |
| `LonelyPianistAVPTests/` | visionOS Swift Testing 单测 | 保障 MusicXML 解析、步骤构建、按键匹配 |
| `Packages/RealityKitContent/` | RealityKit Swift Package 资源 | AVP 相关资源包与跨平台目标约束 |

## 入口点
| 入口 | 位置 | 用途 | 常用命令 / 调用方式 |
| --- | --- | --- | --- |
| macOS App 启动 | `LonelyPianist/LonelyPianistApp.swift` | 初始化容器、服务、ViewModel | `xcodebuild -project LonelyPianist.xcodeproj -scheme LonelyPianist -destination 'platform=macOS' build` |
| visionOS App 启动 | `LonelyPianistAVP/LonelyPianistAVPApp.swift` | Window + ImmersiveSpace 组合 | `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,name=Apple Vision Pro'` |
| Python 服务启动 | `piano_dialogue_server/server/main.py` | 提供 `/health` `/ws` | `python -m uvicorn server.main:app --host 127.0.0.1 --port 8765` |

## 关键产物
| 产物 | 生成方 | 去向 | 说明 |
| --- | --- | --- | --- |
| `RecordingTake` | macOS Recorder / DialogueManager | SwiftData 持久化 | 在 Recorder UI 中可回放、重命名、删除 |
| `MusicXML 文件` | 外部下载或手工准备 | AVP Import | 由用户自行准备并导入 |
| `server_reply.mid` | `server/test_client.py` | `piano_dialogue_server/out/` | 对话服务端到端调试产物 |
| `dialogue_debug/*` | Debug artifact writer | 本地分析目录 | 开启 `DIALOGUE_DEBUG=1` 时落盘 |

## 关键工作流
| 工作流 | 触发点 | 步骤摘要 | 结果 |
| --- | --- | --- | --- |
| MIDI 映射 | Runtime Start + 演奏 | CoreMIDI -> MappingEngine -> KeyboardEventService | 目标应用收到按键输入 |
| Dialogue | Start Dialogue + 静默触发 | 收集短句 -> WS generate -> AI 回放 -> 保存会话 take | 人机轮转演奏 |
| MusicXML 到 AVP | 选择 MusicXML 文件并导入 | AVP 导入 -> step 构建 -> 校准 -> AR Guide | AR Guide 可进入引导态 |

## 示例片段
```swift
// macOS 启动时把 Dialogue 与 Playback 串接到同一 ViewModel
let dialogueManager = DialogueManager(
    clock: clock,
    silenceDetectionService: silenceDetectionService,
    dialogueService: dialogueService,
    recordingRepository: recordingRepository,
    playbackService: playbackService
)
```

```python
# Python 服务只挂载 WS 对话路由
app = FastAPI(title="Piano Dialogue Server", version="0.1.0")
 
```

## 从哪里开始
- 业务入口：先读 [business-context.md](business-context.md)。
- 工程入口：先读 [architecture.md](architecture.md) + [data-flow.md](data-flow.md)。
- 最先定位改动落点：进入 `modules/` 对应页面。

## 如何导航
- `INDEX.md` 提供 **business-first** 与 **engineering-first** 两条阅读路径。
- “要改功能”优先按运行面（macOS/AVP/Python）找模块页。
- “要排故障”优先看 [troubleshooting.md](troubleshooting.md)。
- “要校准配置/环境”看 [configuration.md](configuration.md)。

## 常见陷阱
- 仅启动 macOS App 不等于 Dialogue 可用；`ws://127.0.0.1:8765/ws` 需要后端在线。
- AVP 引导错误先看校准而非直接怀疑匹配算法。
- MusicXML 导入失败时，先确认文件内容与后缀匹配。

## Coverage Gaps
- 未发现仓库内 CI workflow 文件，当前仅能给出本地验证路径。

## 来源引用（Source References）
- `README.md`
- `AGENTS.md`
- `LonelyPianist/LonelyPianistApp.swift`
- `LonelyPianist/ViewModels/LonelyPianistViewModel.swift`
- `LonelyPianistAVP/LonelyPianistAVPApp.swift`
- `LonelyPianistAVP/AppModel.swift`
- `piano_dialogue_server/README.md`
- `piano_dialogue_server/server/main.py`
- `LonelyPianist.xcodeproj/project.pbxproj`
