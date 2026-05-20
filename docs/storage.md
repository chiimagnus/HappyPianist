# 存储

## macOS recorder

| 数据 | 代码位置 | 落盘位置 |
| --- | --- | --- |
| take 列表 | `SwiftDataRecordingTakeRepository` | SwiftData store。 |
| take 实体 | `RecordingTakeEntity`、`RecordedNoteEntity` | `LonelyPianist.store`。 |
| MIDI 导入结果 | `MIDIFileImporter` -> repository | 转成 `RecordingTake` 后进入同一 store。 |

`ModelContainerFactory` 创建 SwiftData container。当前 schema 只包含录制 take 与 note 实体；不要写入 mapping、Dialogue session 或 keyboard injection 相关 store 描述。

## visionOS app

| 数据 | 代码位置 | 默认目录/文件 |
| --- | --- | --- |
| 世界锚点校准 | `WorldAnchorCalibrationStore` | Documents 下 `piano-worldanchor-calibration.json`。 |
| 曲库索引 | `SongLibraryIndexStore` | Documents 下 `SongLibrary/index.json`。 |
| 用户导入曲谱 | `SongFileStore` | Documents 下 `SongLibrary/scores/`。 |
| 用户绑定音频 | `AudioImportService` | Documents 下 `SongLibrary/audio/`。 |
| 练习录制 take | `RecordingTakeStore` | Documents 下 `TakeLibrary/takes.json`。 |

`BundledSongLibraryProvider` 提供 bundle 内置曲目；用户导入曲目通过 `SongLibraryIndex` 与 bundled entries 合并展示。

## Python 服务

| 数据 | 位置 | 说明 |
| --- | --- | --- |
| 调试包 | `piano_dialogue_server/out/dialogue_debug/` | `DIALOGUE_DEBUG=1` 时由 `piano_dialogue_server/server/media/debug_artifacts.py` 写入。 |
| 模型权重 | `AMT_MODEL_DIR` 或本地 `models/` | 不应提交到 git。 |
| 静态前端 | `piano_dialogue_server/static/` | `GET /` 返回 playground。 |

## 清理建议

- 删除 AVP 用户数据时，优先清理 Documents 中的 `SongLibrary/`、`TakeLibrary/` 与 `piano-worldanchor-calibration.json`。
- 删除 Python 调试输出时，只清理 `piano_dialogue_server/out/`；不要删除 `server/` 或 `static/`。
- 删除 macOS recorder 数据时，通过 app 功能删除 take，或清理 app container 中的 SwiftData store。
