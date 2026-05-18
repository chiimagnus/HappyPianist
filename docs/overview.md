# 概览

## 仓库目标
LonelyPianist 是一个 macOS + visionOS + 本地 Python 组成的本机优先钢琴系统。当前产品把钢琴输入拆成三条体验线：macOS MIDI 控制台、Piano Dialogue 对话伙伴、Vision Pro AR 练习教练。工程目标对齐 macOS 26.0、visionOS 26.0，以及本地 Python 3.12 服务。

## 顶层目录
| 路径 | 角色 | 关键内容 | 主要验证入口 |
| --- | --- | --- | --- |
| `LonelyPianist/` | macOS 主应用 | CoreMIDI、映射、Recorder、Dialogue、SwiftData | `LonelyPianist` scheme 的 macOS tests |
| `LonelyPianistAVP/` | visionOS 原型 | Step 1/2/3、AR tracking、MusicXML、曲库、琴键贴皮高亮引导 | `LonelyPianistAVP` scheme 的 visionOS simulator tests |
| `piano_dialogue_server/` | Python 服务 | `/health`、`/generate`、`/ws`、`/upload-expand`、Bonjour 广播、调试包、`static/` | Python smoke scripts + curl + WS client |
| `LonelyPianistTests/` | macOS Swift Testing | 映射、录音、对话、静默检测 | 本地 `xcodebuild test` |
| `LonelyPianistAVPTests/` | AVP Swift Testing | MusicXML、校准、曲库、练习、虚拟钢琴放置 | 本地 `xcodebuild test`（visionOS simulator） |
| `Packages/RealityKitContent/` | RealityKit 包 | visionOS 内容资源，Swift tools 6.2 | AVP build/test graph |
| `docs/` | 仓库知识层 | 业务入口、架构、数据流、模块页 | 文档审阅 |

## 入口文件
| 入口 | 文件 | 说明 |
| --- | --- | --- |
| macOS app | `LonelyPianist/LonelyPianistApp.swift` | 组装 SwiftData、MIDI、mapping、recorder、Dialogue |
| macOS runtime context | `LonelyPianist/AppContext.swift` | 集中持有 ViewModel、services、repositories |
| visionOS app | `LonelyPianistAVP/LonelyPianistAVPApp.swift` | 通过 `AppCompositionRoot` 组装依赖，创建共享 `AppState` / `FlowState` / `ARGuideViewModel` / `WindowCoordinator`，声明 3 个 `Window`（preparation/library/practice）+ `ImmersiveSpace`；窗口导航用 `openWindow(id:)` + 目标窗口 `dismissWindow(id:)` 关闭来源窗口，实现“单窗口可见” |
| AVP guide runtime | `LonelyPianistAVP/ViewModels/ARGuideViewModel.swift` | 练习定位、provider 状态和 immersive runtime |
| AVP practice runtime | `LonelyPianistAVP/ViewModels/PracticeSessionViewModel.swift` | step 匹配、autoplay、贴皮高亮提示 |
| AVP virtual piano | `LonelyPianistAVP/ViewModels/ARGuideViewModel.swift` | 虚拟钢琴放置（准备阶段）、WorldAnchor 复用、键盘几何生成与渲染触发（由钢琴类型驱动） |
| Python app | `piano_dialogue_server/server/api/main.py` | FastAPI + WebSocket 主入口（含 static 挂载与策略分流） |

## 构建与运行
- 本地命令与验证入口统一收敛在 `workflow.md`，避免多处重复。
- 持久化与生成物位置统一收敛在 `storage.md`。

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

## 推荐阅读顺序
1. `business-context.md`：理解产品语义与用户旅程。
2. `architecture.md`：确认三端运行时边界和依赖方向。
3. `data-flow.md`：理解 MIDI、Dialogue、AVP practice、BLE MIDI、CI 的数据/任务流。
4. 进入对应模块页修改功能。
5. `workflow.md`：确认改动应触发哪些本地验证与协作流程。
