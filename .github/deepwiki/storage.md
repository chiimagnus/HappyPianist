# 存储

## 存储面总览
| 存储面 | 路径 / 载体 | 写入方 | 读取方 | 主要内容 |
| --- | --- | --- | --- | --- |
| SwiftData Store（macOS） | `Application Support/<bundle>/LonelyPianist.store` | macOS repositories | macOS ViewModel/Services | 映射配置、录音 take、音符实体 |
| AVP 世界锚点校准 | `Documents/piano-worldanchor-calibration.json` | `WorldAnchorCalibrationStore` | `AppModel` / `ARGuideViewModel` | A0/C8 anchor ID + 键宽 |
| AVP 曲库索引 | `Documents/SongLibrary/index.json` | `SongLibraryIndexStore` | `SongLibraryViewModel` | 曲目条目与最近选择 |
| AVP 曲谱文件 | `Documents/SongLibrary/scores/` | `SongFileStore` | SongLibrary + parser | 导入后的 MusicXML 副本 |
| AVP 音频文件 | `Documents/SongLibrary/audio/` | `AudioImportService` | SongLibrary 播放 | 曲目绑定音频 |
| AVP 种子资源包 | `LonelyPianistAVP/Resources/SeedScores/` | `SongLibrarySeeder` | App 初始化 / 迁移 | 默认 MusicXML + 音频、legacy cleanup |
| Python 调试目录 | `piano_dialogue_server/out/dialogue_debug/*` | `debug_artifacts.py` | 本地排障 | request/response/summary/midi |

## SwiftData 模型与关系（macOS）
| 实体 | 位置 | 关键字段 | 关系 |
| --- | --- | --- | --- |
| `MappingConfigEntity` | `Models/Storage/MappingConfigEntity.swift` | `id/updatedAt/payloadData` | 单条配置 |
| `RecordingTakeEntity` | `Models/Storage/RecordingTakeEntity.swift` | `id/name/createdAt/updatedAt/durationSec` | 1 -> N notes |
| `RecordedNoteEntity` | `Models/Storage/RecordedNoteEntity.swift` | `note/velocity/channel/startOffsetSec/durationSec` | 属于某 take |

## AVP 曲库持久化路径
1. `SongLibrarySeeder.seedAndMigrateIfNeeded()` 启动时先从 `Resources/SeedScores` 注入默认 MusicXML / 音频，并清理旧 `ImportedScores/`。
2. `SongLibraryPaths.ensureDirectoriesExist()` 创建 `SongLibrary/`、`scores/`、`audio/`。
3. `SongFileStore.importMusicXML` 复制文件到 `scores/`，返回导入元信息。
4. `SongLibraryViewModel` 组装 `SongLibraryEntry` 并写回 `index.json`；已有 seed 条目若缺音频，会在后续启动时补齐。
5. 音频绑定时 `AudioImportService` 把文件复制到 `audio/`，再更新条目的 `audioFileName`。

## 数据一致性与恢复
| 场景 | 策略 |
| --- | --- |
| SwiftData 初始化失败 | `ModelContainerFactory` 删除 `store/wal/shm/journal` 后重建 |
| AVP 校准文件不存在 | 读取返回 `nil`，状态为“未设置/待定位” |
| 曲库删除流程 | 先写索引，再删文件；文件删失败会提示“索引已删，文件删除失败” |
| seed/migration | `SongLibrarySeeder` 首次注入 seed 曲与 seed 音频；若 seed 条目已存在则补齐音频，并清理旧 `ImportedScores` 目录 |

## 文件命名与安全
- 曲谱和音频导入文件采用时间戳前缀，避免同名覆盖。
- 文件名通过 `lastPathComponent` 限定，防止路径穿越。
- 索引 JSON 使用 ISO8601 日期编解码与原子写入。

## 风险与注意事项
- `ModelContainerFactory` 的删库恢复可提升可用性，但会丢历史数据。
- 曲库存在“索引与文件最终一致性”窗口：异常中断时可能遗留孤儿文件。
- 当前无内建垃圾回收任务处理长期累积导入文件。

## Coverage Gaps
- 尚未见 schema 版本化迁移策略文档（SwiftData 与曲库索引都依赖代码内兼容处理）。
