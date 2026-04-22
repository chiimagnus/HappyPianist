# 概览

## 仓库目标与产品线
- **总体目标**：构建一个本机优先（local-first）的跨端钢琴交互系统。
- **三条运行面**：
  1. macOS：MIDI 监听、映射、录制、Dialogue 控制台；
  2. visionOS：Step 1/2/3 练习流程（校准、选曲、练习）；
  3. Python：`/health` + `/ws` 对话推理服务。

## 一句话心智模型
- macOS 负责“输入采集 + 业务编排”，Python 负责“回应生成”，AVP 负责“空间定位 + 可视化引导”。
- 核心跨边界数据：`MIDIEvent`、`RecordingTake`、`DialogueNote`、`PracticeStep`、`StoredWorldAnchorCalibration`、`SongLibraryIndex`。

## 顶层目录与职责
| 路径 | 职责 | 为什么重要 |
| --- | --- | --- |
| `LonelyPianist/` | macOS 主应用（MVVM + Services） | 改映射、录制、Dialogue 的主落点 |
| `LonelyPianistAVP/` | visionOS 三步流与沉浸式引导 | 改校准、曲库、定位策略、高亮逻辑 |
| `piano_dialogue_server/` | Python 推理与 WS 协议 | 改生成逻辑、模型加载、调试产物 |
| `LonelyPianistTests/` | macOS Swift Testing | 回归映射/录制/静默检测 |
| `LonelyPianistAVPTests/` | AVP Swift Testing | 回归解析/步骤/曲库/定位策略 |
| `Packages/RealityKitContent/` | RealityKit Swift Package | AVP target 的包依赖与平台约束 |

## 主要入口点
| 入口 | 文件 | 用途 |
| --- | --- | --- |
| macOS App | `LonelyPianist/LonelyPianistApp.swift` | 依赖注入与主窗口启动 |
| AVP App | `LonelyPianistAVP/LonelyPianistAVPApp.swift` | `WindowGroup + ImmersiveSpace` 场景启动 |
| AVP 三步入口 | `LonelyPianistAVP/Views/ContentView.swift` | Step 1 校准、Step 2 选曲、Step 3 练习导航 |
| Python 服务 | `piano_dialogue_server/server/main.py` | FastAPI + WebSocket 路由入口 |

## 核心产物与状态落点
| 产物 | 生成方 | 存储位置 |
| --- | --- | --- |
| 映射配置 / 录音 take | macOS repositories | `Application Support/.../LonelyPianist.store` |
| 世界锚点校准 | AVP 校准流程 | `Documents/piano-worldanchor-calibration.json` |
| 曲库索引与文件 | AVP Song Library | `Documents/SongLibrary/index.json` + `scores/` + `audio/` |
| AVP 默认种子曲与试听状态 | AVP 启动 + 曲库页 | bundled `Resources/SeedScores/` -> `Documents/SongLibrary/*` + `currentListeningEntryID` |
| 对话调试包 | Python server | `piano_dialogue_server/out/dialogue_debug/` |

## 关键工作流（跨页路由）
| 工作流 | 入口 | 继续阅读 |
| --- | --- | --- |
| MIDI 映射与录制 | macOS 主窗口 | `modules/lonelypianist-macos.md` |
| 对话生成与回放 | Dialogue 页面 + Python `/ws` | `modules/piano-dialogue-server.md` + `data-flow.md` |
| AVP 三步练习 | AVP `ContentView` | `modules/lonelypianist-avp.md` |

## 示例片段
```swift
let appModel = AppModel()
appModel.loadStoredCalibrationIfPossible()
let songLibrarySeeder = SongLibrarySeeder()
try? songLibrarySeeder.seedAndMigrateIfNeeded()
```

```python
app = FastAPI(title="Piano Dialogue Server", version="0.1.0")
```

## Coverage Gaps
- `.github/workflows/` 为空，当前文档仅能描述“本地验证链路”。
- 仓库缺少共享 `LonelyPianistAVP.xcscheme`，跨机器命令稳定性受影响。
