# 术语表

## 说明
- 本页统一仓库中的业务与工程术语，优先使用代码真实命名。
- 当术语在不同页面出现时，应保持同一含义，避免“同词多义”。

## 业务术语
| 术语 | 定义 | 常见位置 | 为什么重要 |
| --- | --- | --- | --- |
| Piano Dialogue | 你弹一句、AI 回一句的轮转式流程 | macOS Dialogue + Python WS | 跨进程核心体验 |
| AR Guide Step 1/2/3 | 校准、选曲、练习三步流 | AVP `ContentView` | AVP 主业务入口 |
| Take | 一次录音/会话产物（含音符数组） | Recorder / Dialogue | 回放与持久化单位 |

## 架构术语
| 术语 | 定义 | 常见位置 | 为什么重要 |
| --- | --- | --- | --- |
| `MIDIEvent` | 统一 MIDI 输入事件模型 | `LonelyPianist/Models/MIDI` | 映射/录制/对话共同输入 |
| `DialogueNote` | Swift 与 Python 共享的音符契约 | `Models/Dialogue` + `server/protocol.py` | 跨进程一致性关键 |
| `PracticeStep` | AVP 练习步进数据单元 | `Models/Practice` | 引导推进粒度 |
| `DataProviderState` | AR provider 运行状态枚举 | `ARTrackingService` | 定位失败诊断核心 |
| `SongAudioPlaybackStateController` | AVP 曲库试听按钮的播放态控制器 | `SongLibraryViewModel` + `SongAudioPlayer` | 统一 `currentListeningEntryID` 与播放/暂停状态 |

## 存储术语
| 术语 | 定义 | 常见位置 | 为什么重要 |
| --- | --- | --- | --- |
| `StoredWorldAnchorCalibration` | A0/C8 世界锚点校准模型 | AVP `Models/Calibration` | Step 3 定位输入 |
| `SongLibraryIndex` | 曲库索引模型（entries + lastSelectedEntryID） | AVP `Models/Library` | 曲库一致性中心 |
| `SongLibraryEntry` | 单曲目条目（曲谱+可选音频） | AVP `Models/Library` | 选曲页面核心数据 |
| `SongLibrarySeeder` | 启动时从 bundled `Resources/SeedScores` 注入默认曲目与音频，并清理旧目录 | AVP `Services/Library` | 首开可用性与迁移入口 |
| `dialogue_debug bundle` | 服务端调试落盘工件集合 | `server/debug_artifacts.py` | 线上下问题复盘抓手 |

## 易混淆概念
- **stored calibration** 与 **runtime calibration**：
  - 前者是持久化 anchor 标识；
  - 后者是当前场景内通过 tracked anchors 解析出的几何结果。
- **曲库导入成功** 与 **可开始练习**：
  - 导入成功仅代表文件和索引写入成功；
  - 进入练习还要求可解析为有效 steps 且定位成功。

## Coverage Gaps
- 发布/版本语义目前仍分散在 README 与提交流程中，尚无独立版本治理页面。
