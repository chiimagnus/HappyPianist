# 术语表

## 说明
- 本页统一仓库中的业务与工程术语，避免跨页面出现“同义不同名”。
- 术语优先采用代码中的真实命名，再补充中文语义。

## 业务术语
| 术语 | 定义 | 常见位置 | 为什么重要 |
| --- | --- | --- | --- |
| Piano Dialogue | 轮转式钢琴对话：人弹一段，AI 回一段 | `LonelyPianist/README.md`、`server/main.py` | 是跨 macOS + Python 的核心产品能力 |
| AR Guide | visionOS 中按步骤高亮键位的练习模式 | `LonelyPianistAVP/README.md`、`ImmersiveView.swift` | 是 AVP 产品线主体验 |
| Take | 一次录音或会话产物（含音符数组） | `RecordingTake.swift`、Recorder UI | 持久化与回放的基本单位 |

## 架构 / 工程术语
| 术语 | 定义 | 常见位置 | 为什么重要 |
| --- | --- | --- | --- |
| `MIDIEvent` | 统一 MIDI 输入事件模型 | `Models/MIDI/MIDIEvent.swift` | 映射、录音、对话共享输入 |
| `MappingConfigPayload` | 映射规则载体（single/chord/velocity） | `Models/Mapping/MappingConfig.swift` | 决定按键输出行为 |
| `DialogueNote` | 客户端与服务端共用音符契约 | Swift `Models/Dialogue` + Python `protocol.py` | 跨进程协议一致性关键 |
| `PracticeStep` | AVP 引导步骤（同一 tick 的音符集合） | `Models/Practice/PracticeStep.swift` | 决定引导推进粒度 |

## 运行 / 发布术语
| 术语 | 定义 | 常见位置 | 为什么重要 |
| --- | --- | --- | --- |
| `DIALOGUE_DEBUG` | 服务端调试落盘开关（`1` 为开启） | `server/debug_artifacts.py` | 排查推理链路问题首选 |
| `AMT_MODEL_DIR` | 模型目录环境变量 | `server/inference.py`、README | 控制模型来源与离线能力 |
| `ImmersiveSpace` | visionOS 沉浸式空间场景 | `LonelyPianistAVPApp.swift` | AR Guide 的运行容器 |

## 易混淆概念
- **Recorder take vs Dialogue session take**：两者结构同为 `RecordingTake`，但后者会混合 human + AI note。
- **Chord 匹配（macOS）vs Step 匹配（AVP）**：前者是“按下集合严格相等触发动作”，后者支持容差并可在时间窗口累积。

## Coverage Gaps
- 尚未见仓库内对“发布/版本术语”形成统一约定文档（当前以 README 与代码注释为主）。

## 来源引用（Source References）
- `LonelyPianist/README.md`
- `LonelyPianistAVP/README.md`
- `piano_dialogue_server/README.md`
- `LonelyPianist/Models/Recording/RecordingTake.swift`
- `LonelyPianist/Models/Dialogue/DialogueNote.swift`
- `piano_dialogue_server/server/protocol.py`
- `piano_dialogue_server/server/debug_artifacts.py`
- `LonelyPianistAVP/LonelyPianistAVPApp.swift`
