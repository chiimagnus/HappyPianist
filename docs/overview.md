# 概览

## 仓库目标
LonelyPianist 是一个 macOS + visionOS + 本地 Python 组成的本机优先钢琴系统。当前产品把钢琴输入拆成三条体验线：macOS MIDI 控制台、Piano Dialogue 对话伙伴、Vision Pro AR 练习教练。工程目标对齐 macOS 26.0、visionOS 26.0，以及本地 Python 3.12 服务。

## 构建与运行
- 本地命令与验证入口统一收敛在 `workflow.md`，避免多处重复。
- 持久化与生成物位置统一收敛在 `storage.md`。

## 产品定位
LonelyPianist 是一个本地优先的钢琴交互系统，围绕三条产品线展开：
1. macOS 把 MIDI 变成控制、录音和对话；
2. visionOS 把导入的 MusicXML 变成空间引导练习；
3. Python 把短句钢琴输入变成 AI 回复（并提供 MIDI 上传扩展工具与最小 Web UI）。

## 用户旅程
| 旅程 | 输入 | 可见结果 | 下一跳 |
| --- | --- | --- | --- |
| MIDI 快捷控制 | MIDI 键盘事件 | 目标 App 收到系统按键/文本 | [modules/lonelypianist-macos-mapping.md](modules/lonelypianist-macos-mapping.md) |
| Piano Dialogue | 静默窗口内的演奏片段 | AI 回放并落盘为 take | [modules/lonelypianist-macos-dialogue.md](modules/lonelypianist-macos-dialogue.md) |
| AR Guide | MusicXML + A0/C8 校准 + 手势 | 双谱表五线谱 + 左右手键位高亮 + 步骤推进（可选按手分别判定） | [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md) |
| AR Guide（虚拟钢琴） | MusicXML + 钢琴类型=虚拟钢琴 + 手势放置（准备阶段） | 3D 88 键键盘 + 实时发声 + 步骤推进 | [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md) |
| AR Guide（蓝牙 MIDI） | MusicXML + 蓝牙 MIDI 连接 + 校准 | 键位高亮与步骤推进 + Take 录制/回放 | [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md) |
| AVP AI 即兴（后端生成） | 练习中的短句片段（真实/虚拟/BLE MIDI 输入） | 自动发现后端、生成续写并在沉浸空间中回放 | [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md) + [modules/piano-dialogue-server.md](modules/piano-dialogue-server.md) |

## 功能地图
| 运行面 | 用户能做什么 | 读哪一页 |
| --- | --- | --- |
| macOS Runtime | 监听来源、看事件、切换输出 | [modules/lonelypianist-macos-runtime.md](modules/lonelypianist-macos-runtime.md) |
| macOS Mappings | 配置单键 / 和弦 / velocity 规则 | [modules/lonelypianist-macos-mapping.md](modules/lonelypianist-macos-mapping.md) |
| macOS Recorder | 录 take、导入 MIDI、回放 take | [modules/lonelypianist-macos-recording.md](modules/lonelypianist-macos-recording.md) |
| macOS Dialogue | turn-based 钢琴对话 | [modules/lonelypianist-macos-dialogue.md](modules/lonelypianist-macos-dialogue.md) |
| visionOS Library | 导入 MusicXML、绑定音频、试听、删除 | [modules/lonelypianist-avp-library.md](modules/lonelypianist-avp-library.md) |
| visionOS Calibration | A0/C8 校准与保存 | [modules/lonelypianist-avp-calibration.md](modules/lonelypianist-avp-calibration.md) |
| visionOS Practice | 定位、自动推进、按键贴皮高亮引导、双谱表五线谱、左右手区分、虚拟钢琴模式、（可选）左右手分别匹配 | [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md) |
| visionOS BLE MIDI | 蓝牙 MIDI 连接、Take 录制/回放、Phrase 录制 | [modules/lonelypianist-avp.md](modules/lonelypianist-avp.md) |
| visionOS AI Improv | 自动发现后端、上传短句请求生成、沉浸式回放 | [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md) + [modules/piano-dialogue-server.md](modules/piano-dialogue-server.md) |
| Python Server | 接收 generate 请求、返回回复 notes；提供 MIDI 上传扩展与最小前端 | [modules/piano-dialogue-server.md](modules/piano-dialogue-server.md) |

## 按问题导航
- **要改 macOS 监听 / 映射 / 录音 / 对话**：看 `modules/lonelypianist-macos.md`，再下钻对应子页。
- **要改 AVP 导入 / 校准 / 练习 / MusicXML**：看 `modules/lonelypianist-avp.md`，再下钻对应子页。
- **要改 MusicXML 双 part 归一化（左手音符丢失）**：看 `modules/lonelypianist-avp-musicxml.md` 的「钢琴双 part 归一化」章节。
- **要改五线谱渲染（stems/beams/flags/SMuFL）**：看 `modules/lonelypianist-avp-practice.md` 的「双谱表五线谱」章节。
- **要改 AR 引导贴皮高亮**：看 `modules/lonelypianist-avp-practice.md` 和 `PianoGuideOverlayController`。
- **要改虚拟钢琴**：看 `modules/lonelypianist-avp-practice.md` 的「虚拟钢琴模式」章节，涉及放置状态机、按键检测、3D 渲染和实时发声。
- **要改蓝牙 MIDI 模式 / Take 录制**：看 `modules/lonelypianist-avp.md` 的「Bluetooth MIDI（BLE）」章节和 `modules/lonelypianist-avp-practice.md` 的三种钢琴模式表。
- **要改 Python 协议或采样逻辑**：看 `modules/piano-dialogue-server.md` 与 `modules/piano-dialogue-server-inference.md`。
- **要运行测试 / 本地验证**：见 `workflow.md`。
- **要手动格式化**：见 `configuration.md`（`.swiftformat`）。
- **遇到运行异常**：从 `troubleshooting.md` 开始。
