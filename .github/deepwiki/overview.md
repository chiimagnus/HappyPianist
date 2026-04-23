# 概览

## 仓库目标
这是一个 macOS + visionOS + 本地 Python 组成的本机优先钢琴系统。

## 顶层目录
| 路径 | 角色 | 关键内容 |
| --- | --- | --- |
| `LonelyPianist/` | macOS 主应用 | CoreMIDI、映射、Recorder、Dialogue |
| `LonelyPianistAVP/` | visionOS 原型 | Step 1/2/3、AR tracking、MusicXML、曲库 |
| `piano_dialogue_server/` | Python 服务 | `/health`、`/ws`、推理和调试包 |
| `LonelyPianistTests/` | macOS Swift Testing | 映射、录音、对话、静默检测 |
| `LonelyPianistAVPTests/` | AVP Swift Testing | MusicXML、校准、曲库、练习 |
| `Packages/RealityKitContent/` | RealityKit 包 | visionOS 内容资源 |

## 入口文件
| 入口 | 文件 | 说明 |
| --- | --- | --- |
| macOS app | `LonelyPianist/LonelyPianistApp.swift` | 组装 SwiftData、MIDI、mapping、recorder、Dialogue |
| visionOS app | `LonelyPianistAVP/LonelyPianistAVPApp.swift` | 组装 AppModel、曲库 seed、WindowGroup + ImmersiveSpace |
| Python app | `piano_dialogue_server/server/main.py` | FastAPI + WebSocket 主入口 |

## 功能地图
| 运行面 | 用户能做什么 | 读哪一页 |
| --- | --- | --- |
| macOS Runtime | 监听来源、看事件、切换输出 | [modules/lonelypianist-macos-runtime.md](modules/lonelypianist-macos-runtime.md) |
| macOS Mappings | 配置单键 / 和弦 / velocity 规则 | [modules/lonelypianist-macos-mapping.md](modules/lonelypianist-macos-mapping.md) |
| macOS Recorder | 录 take、导入 MIDI、回放 take | [modules/lonelypianist-macos-recording.md](modules/lonelypianist-macos-recording.md) |
| macOS Dialogue | turn-based 钢琴对话 | [modules/lonelypianist-macos-dialogue.md](modules/lonelypianist-macos-dialogue.md) |
| visionOS Library | 导入 MusicXML、绑定音频、试听、删除 | [modules/lonelypianist-avp-library.md](modules/lonelypianist-avp-library.md) |
| visionOS Calibration | A0/C8 校准与保存 | [modules/lonelypianist-avp-calibration.md](modules/lonelypianist-avp-calibration.md) |
| visionOS Practice | 定位、自动推进、按键高亮 | [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md) |
| Python Server | 接收 generate 请求、返回回复 notes | [modules/piano-dialogue-server-protocol.md](modules/piano-dialogue-server-protocol.md) |

## 生成物与持久化
| 产物 | 来源 | 去向 |
| --- | --- | --- |
| SwiftData store | macOS repositories | `Application Support/.../LonelyPianist.store` |
| 世界锚点校准 | AVP Step 1 | `Documents/piano-worldanchor-calibration.json` |
| 曲库索引 | AVP Step 2 | `Documents/SongLibrary/index.json` |
| 曲谱与音频副本 | AVP 导入流程 | `Documents/SongLibrary/scores|audio` |
| Python 调试包 | `DIALOGUE_DEBUG=1` | `piano_dialogue_server/out/dialogue_debug` |

## 阅读顺序建议
1. `business-context.md`
2. `architecture.md`
3. `data-flow.md`
4. 进入对应模块页

## Coverage Gaps
- `.github/workflows/` 仍为空；此页只能描述本地可执行入口，不能声明 CI 已存在。
