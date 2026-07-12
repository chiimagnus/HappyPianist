# 存储

HappyPianistAVP 当前使用 Documents 目录中的 JSON 和用户导入文件；不使用 SwiftData。

## 文件布局

| 数据 | 代码 | 默认位置 |
| --- | --- | --- |
| 世界锚点校准 | `WorldAnchorCalibrationStore` | `Documents/piano-worldanchor-calibration.json` |
| 曲库索引 | `SongLibraryIndexStore` | `Documents/SongLibrary/index.json` |
| 用户曲谱 | `SongFileStore` | `Documents/SongLibrary/scores/` |
| 用户试听音频 | `AudioImportService` | `Documents/SongLibrary/audio/` |
| 练习录制 take | `RecordingTakeStore` | `Documents/TakeLibrary/takes.json` |
| 小节级练习进度 | `FilePracticeProgressRepository` | `Documents/PracticeProgress/progress-v1.json` |
| 可导出诊断日志 | `FileDiagnosticsStore` | `Documents/Diagnostics/diagnostics-YYYY-MM-DD.jsonl` |

bundled MusicXML 和 App 资源来自 bundle，不写入 Documents。

## 曲库

`SongLibraryIndex` 只保存用户导入 entry 与最后选择项。bundled entries 由 `BundledSongLibraryProvider` 在启动时扫描后合并。

导入流程：

1. `SongFileStore` 复制文件到 `Documents/SongLibrary/scores/`。
2. `SongLibraryViewModel` 生成 UUID 和 index entry。
3. `SongLibraryIndexStore` 原子写入 index。
4. index 保存失败时删除刚复制的 score，避免孤儿文件。

删除用户曲目时同时删除曲谱、绑定音频和对应 song UUID 的练习进度。进度清理失败不回滚已完成的曲目删除。

## 练习进度

`progress-v1.json` 按 `song UUID + score revision digest` 区分曲谱版本，保存：

- active round configuration
- resume point
- source-measure facts
- 更新时间

不保存：

- SwiftUI presentation state
- cue、summary、hotspot 或 restoration map
- RealityKit entity 状态
- AI 文案或生成内容
- 原始逐帧麦克风、MIDI 或手部数据

当前 v1 使用严格 Codable 结构。损坏、缺字段或不受支持的数据返回明确错误，不通过推测默认值悄悄迁移。

`PracticeProgressCoordinator` 串行化 checkpoint，并用 song identity、round generation 与 progress generation 防止旧任务覆盖新状态。back、background、session replacement 和 completion 必须等待 flush。


## 诊断日志

`AppDiagnosticsReporter` 是业务代码的统一诊断入口。每个事件先进入 `os.Logger`；只有 `persistence == .exportable` 的低频事件才追加到每日 JSONL 文件。

规则：

- 默认保留7 个日历日，App 启动、写入与导出前执行清理。
- 导出 ZIP 固定包含 `diagnostics.jsonl`、`diagnostics.txt`、`environment.txt`。
- 导出由用户主动触发，不自动上传。
- 文件引用只保存文件名和 App 内相对路径。
- 不保存原始曲谱、逐音 MIDI、音频样本、手部帧、AI 正文、密钥、认证头或绝对路径。
- 写入失败只影响可导出副本，系统日志仍记录失败；不得阻止曲库或练习流程。

## Take library

`RecordingTakeStore` 使用 ISO 8601 日期编码，将全部 takes 原子写入 `takes.json`。MIDI 导出由 `RecordingMIDIExportService` 临时生成，不自动保存在 Documents。

## 清理

重置 AVP 用户数据时，根据需要清理：

```text
Documents/SongLibrary/
Documents/TakeLibrary/
Documents/PracticeProgress/
Documents/Diagnostics/
Documents/piano-worldanchor-calibration.json
```

不要删除 App bundle 资源，也不要把测试 fixture 当作用户数据。
