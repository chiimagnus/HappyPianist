# 概览

## 仓库目标
LonelyPianist 是一个 macOS + visionOS + 本地 Python 组成的本机优先钢琴系统。当前产品把钢琴输入拆成三条体验线：macOS MIDI 控制台、Piano Dialogue 对话伙伴、Vision Pro AR 练习教练。工程目标对齐 macOS 26.0、visionOS 26.0，以及本地 Python 3.12 服务。

## 顶层目录
| 路径 | 角色 | 关键内容 | 主要验证入口 |
| --- | --- | --- | --- |
| `LonelyPianist/` | macOS 主应用 | CoreMIDI、映射、Recorder、Dialogue、SwiftData | `LonelyPianist` scheme 的 macOS tests |
| `LonelyPianistAVP/` | visionOS 原型 | Step 1/2/3、AR tracking、MusicXML、曲库、光柱引导 | `LonelyPianistAVP` scheme 的 visionOS simulator tests |
| `piano_dialogue_server/` | Python 服务 | `/health`、`/ws`、推理、调试包 | Python smoke scripts + WS client |
| `LonelyPianistTests/` | macOS Swift Testing | 映射、录音、对话、静默检测 | PR Tests / macOS tests |
| `LonelyPianistAVPTests/` | AVP Swift Testing | MusicXML、校准、曲库、练习 | PR Tests / AVP tests |
| `Packages/RealityKitContent/` | RealityKit 包 | visionOS 内容资源，Swift tools 6.2 | AVP build/test graph |
| `.github/workflows/` | CI / quality 自动化 | PR tests、SwiftFormat/SwiftLint | GitHub Actions |

## 入口文件
| 入口 | 文件 | 说明 |
| --- | --- | --- |
| macOS app | `LonelyPianist/LonelyPianistApp.swift` | 组装 SwiftData、MIDI、mapping、recorder、Dialogue |
| macOS runtime context | `LonelyPianist/AppContext.swift` | 集中持有 ViewModel、services、repositories |
| visionOS app | `LonelyPianistAVP/LonelyPianistAVPApp.swift` | 组装 AppModel、曲库 seed、WindowGroup + ImmersiveSpace |
| AVP guide runtime | `LonelyPianistAVP/ViewModels/ARGuideViewModel.swift` | 练习定位、provider 状态和 immersive runtime |
| AVP practice runtime | `LonelyPianistAVP/ViewModels/PracticeSessionViewModel.swift` | step 匹配、反馈、autoplay、光柱提示 |
| AVP virtual piano | `LonelyPianistAVP/ViewModels/VirtualPianoPlacementViewModel.swift` | 虚拟钢琴放置状态机、88 键几何、按键检测 |
| Python app | `piano_dialogue_server/server/main.py` | FastAPI + WebSocket 主入口 |

## 构建与 CI 入口
| 入口 | 当前状态 | 命令 / 触发条件 |
| --- | --- | --- |
| macOS scheme | 已在 CI 验证 | `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianist -destination 'platform=macOS'` |
| visionOS scheme | 已在 CI 验证 | `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,name=Apple Vision Pro'` |
| PR Tests | 只在 `pull_request` 触发 | 按路径分流 macOS / AVP tests，runner 为 `macos-26` |
| Swift Quality | 只手动触发 | `workflow_dispatch`，运行 SwiftFormat + SwiftLint autocorrect 并提交格式化结果 |
| Python service | 本地手动运行 | `python -m uvicorn server.main:app --host 127.0.0.1 --port 8765` |

## 功能地图
| 运行面 | 用户能做什么 | 读哪一页 |
| --- | --- | --- |
| macOS Runtime | 监听来源、看事件、切换输出 | [modules/lonelypianist-macos-runtime.md](modules/lonelypianist-macos-runtime.md) |
| macOS Mappings | 配置单键 / 和弦 / velocity 规则 | [modules/lonelypianist-macos-mapping.md](modules/lonelypianist-macos-mapping.md) |
| macOS Recorder | 录 take、导入 MIDI、回放 take | [modules/lonelypianist-macos-recording.md](modules/lonelypianist-macos-recording.md) |
| macOS Dialogue | turn-based 钢琴对话 | [modules/lonelypianist-macos-dialogue.md](modules/lonelypianist-macos-dialogue.md) |
| visionOS Library | 导入 MusicXML、绑定音频、试听、删除 | [modules/lonelypianist-avp-library.md](modules/lonelypianist-avp-library.md) |
| visionOS Calibration | A0/C8 校准与保存 | [modules/lonelypianist-avp-calibration.md](modules/lonelypianist-avp-calibration.md) |
| visionOS Practice | 定位、自动推进、按键光柱引导、虚拟钢琴模式 | [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md) |
| Python Server | 接收 generate 请求、返回回复 notes | [modules/piano-dialogue-server-protocol.md](modules/piano-dialogue-server-protocol.md) |

## 生成物与持久化
| 产物 | 来源 | 去向 | 风险点 |
| --- | --- | --- | --- |
| SwiftData store | macOS repositories | `Application Support/.../LonelyPianist.store` | schema 调整需关注迁移 |
| 世界锚点校准 | AVP Step 1 | `Documents/piano-worldanchor-calibration.json` | 缺失时 Step 3 无法定位 |
| 曲库索引 | AVP Step 2 | `Documents/SongLibrary/index.json` | index 和文件副本可能漂移 |
| 曲谱与音频副本 | AVP 导入流程 | `Documents/SongLibrary/scores|audio` | 删除/重导入要同步索引 |
| Python 调试包 | `DIALOGUE_DEBUG=1` | `piano_dialogue_server/out/dialogue_debug` | 可能包含本地输入片段 |
| `.xcresult` | GitHub Actions / xcodebuild | runner DerivedData | 失败时优先看 build/test failure |

## 推荐阅读顺序
1. `business-context.md`：理解产品语义与用户旅程。
2. `architecture.md`：确认三端运行时边界和依赖方向。
3. `data-flow.md`：理解 MIDI、Dialogue、AVP practice、CI 的数据/任务流。
4. 进入对应模块页修改功能。
5. `testing.md` 和 `workflow.md`：确认改动应触发哪些测试与流程。

## Coverage Gaps
- 仓库已有 PR 级 macOS/AVP 测试和手动 Swift Quality，但尚没有统一发布流水线。
- Python 服务仍以本地运行和 smoke script 为主，未纳入 GitHub Actions 自动门禁。

## 更新记录（Update Notes）
- 2026-04-25: 更新 CI、AVP simulator test、Swift Quality 手动触发、光柱引导和 `macos-26` 事实。
- 2026-04-30: 新增虚拟钢琴入口文件和功能地图条目。
