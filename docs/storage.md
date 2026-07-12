# 存储

## macOS recorder

| 数据 | 代码位置 | 落盘位置 |
| --- | --- | --- |
| take 列表 | `SwiftDataRecordingTakeRepository` | SwiftData store。 |
| take 实体 | `RecordingTakeEntity`、`RecordedNoteEntity` | `HappyPianist.store`。 |
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

## 清理建议

- 删除 AVP 用户数据时，优先清理 Documents 中的 `SongLibrary/`、`TakeLibrary/` 与 `piano-worldanchor-calibration.json`。
- 删除 macOS recorder 数据时，通过 app 功能删除 take，或清理 app container 中的 SwiftData store。

## visionOS 练习进度

| 数据 | 代码位置 | 默认目录/文件 |
| --- | --- | --- |
| 小节级练习进度 | `FilePracticeProgressRepository` | Documents 下 `PracticeProgress/progress-v1.json`。 |

`progress-v1.json` 的文件名定义 v1 格式，按 `SongLibraryEntry.id + score revision digest` 区分曲谱版本。v1 使用严格解码；缺字段、损坏或不受支持的数据会被视为不可恢复的旧进度，而不会通过推测默认值继续运行。内容只保存练习事实：active configuration、resume point 与 source-measure facts；不保存 SwiftUI 状态、动画、AI 文案或原始逐帧输入。

写入由 `PracticeProgressCoordinator` 串行化并原子落盘。快速 checkpoint 会合并；back、background、session replacement 与 completion 必须 await flush。删除用户曲目时同时按 song UUID 清理进度；进度清理失败不会回滚已经完成的曲库删除。
