# 业务入口

## 产品定位
LonelyPianist 是一个本地优先的钢琴交互系统，围绕三条产品线展开：
1. macOS 把 MIDI 变成控制、录音和对话；
2. visionOS 把导入的 MusicXML 变成空间引导练习；
3. Python 把短句钢琴输入变成 AI 回复。

## 三条用户旅程
| 旅程 | 输入 | 可见结果 | 下一跳 |
| --- | --- | --- | --- |
| MIDI 快捷控制 | MIDI 键盘事件 | 目标 App 收到系统按键/文本 | [modules/lonelypianist-macos-mapping.md](modules/lonelypianist-macos-mapping.md) |
| Piano Dialogue | 静默窗口内的演奏片段 | AI 回放并落盘为 take | [modules/lonelypianist-macos-dialogue.md](modules/lonelypianist-macos-dialogue.md) |
| AR Guide | MusicXML + A0/C8 校准 + 手势 | 键位高亮与步骤推进 | [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md) |
| AR Guide（虚拟钢琴） | MusicXML + 虚拟钢琴开关 + 手势放置 | 3D 88 键键盘 + 实时发声 + 步骤推进 | [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md) |

## 业务规则
| 规则 | 含义 | 影响面 |
| --- | --- | --- |
| 权限先于动作 | macOS 需要 Accessibility；AVP 需要 Hand/World tracking 权限 | 启动和排障 |
| 对话是 turn-based | 静默触发后再生成回复，回放策略可配置 | macOS + Python |
| Step 3 前置条件明确 | 必须先导入谱面并有可用校准（虚拟钢琴模式仅需导入谱面） | AVP 进入练习 |
| 曲库索引与文件必须一致 | 导入 / 删除 / 音频绑定都先后写盘 | AVP 存储和恢复 |

## 核心产物
| 产物 | 由谁生成 | 存储位置 |
| --- | --- | --- |
| `MappingConfig` / `RecordingTake` | macOS repositories | SwiftData store |
| `Dialogue take` | macOS DialogueManager | SwiftData store |
| `piano-worldanchor-calibration.json` | AVP Step 1 | Documents |
| `SongLibrary/index.json` + scores/audio | AVP 曲库 | Documents/SongLibrary |
| `out/dialogue_debug/*` | Python server | 本地调试目录 |

## 术语路由
| 术语 | 业务含义 | 技术页 |
| --- | --- | --- |
| Runtime | MIDI 监听和状态反馈面板 | [modules/lonelypianist-macos-runtime.md](modules/lonelypianist-macos-runtime.md) |
| Mappings | 单键/和弦映射编辑器 | [modules/lonelypianist-macos-mapping.md](modules/lonelypianist-macos-mapping.md) |
| Recorder | take 录制、导入与播放 | [modules/lonelypianist-macos-recording.md](modules/lonelypianist-macos-recording.md) |
| Step 1 / 2 / 3 | 校准、选曲、练习 | [modules/lonelypianist-avp.md](modules/lonelypianist-avp.md) |
| `/ws` | 对话协议入口 | [modules/piano-dialogue-server-protocol.md](modules/piano-dialogue-server-protocol.md) |

## 继续阅读
- 全局目录与入口：`overview.md`
- 依赖与平台约束：`dependencies.md`
- 流程细节：`data-flow.md`
- 故障定位：`troubleshooting.md`

## Coverage Gaps
- 业务入口页只描述已在仓库中出现的能力；未包含任何尚未实现的产品路线图。
