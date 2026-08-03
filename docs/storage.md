# 存储

每个 App host 在自己的 sandbox Documents 下使用 JSON 和用户导入文件，不使用 SwiftData。路径、schema 和删除行为必须一起修改；macOS host 不迁移或共享 visionOS container。

## 文件布局

| 数据 | owner | 默认位置 |
| --- | --- | --- |
| 真实钢琴 world-anchor 校准 | `WorldAnchorCalibrationStore` | `Documents/piano-worldanchor-calibration.json` |
| 用户曲库索引 | `SongLibraryIndexStore` | `Documents/SongLibrary/index.json` |
| 用户曲谱 / 试听音频 | `SongLibraryImportTransactionService`、`SongFileStore`、`AudioImportService` | `Documents/SongLibrary/scores/`、`audio/` |
| 导入事务 | `SongLibraryImportTransactionService` | `Documents/SongLibrary/transactions/<operation-id>/` |
| 练习 progress / session | `FilePracticeProgressRepository` | `Documents/PracticeProgress/progress-v1.json` |
| MIDI take | `RecordingTakeStore` | `Documents/TakeLibrary/takes.json` |
| 可导出诊断 | `FileDiagnosticsStore` | `Documents/Diagnostics/diagnostics-YYYY-MM-DD.jsonl` |

bundled MusicXML、字体、SoundFont 和 CoreML 资源属于 App bundle，不写入 Documents。

## 曲库索引与导入

- index 只保存用户 entry 和最后选择项；bundled entry 每次由 provider 扫描并合并。
- entry 用 `song UUID + scoreFileVersionID` 区分曲谱版本；版本缺失或非空 index 无法解码时 fail closed，保留原文件。
- 导入按 operation ID 排队：同卷 `.partial` → 字节数/SHA-256 fingerprint → staged journal → target/index commit。
- 冲突在 target/index mutation 前暂停，用户确认只回传 operation ID；actor 重新读取最新事实后再决定 replace、repair 或 orphan adopt。
- bootstrap 先恢复未完成 transaction，再读 index，最后扫描 bundle。journal 只含相对文件名、phase、identity 和 fingerprint，不含 URL、曲谱正文或完整 index。
- macOS 通过 `fileImporter` 只在暂存副本期间持有 security scope；index、journal、score metadata 与 progress 均不得写入选中的外部 URL、bookmark 或绝对路径。
- macOS 试听音频也由 `Library.AudioImportService` 在同一 sandbox 规则下复制到 `SongLibrary/audio/`；index 只保存安全相对文件名。替换成功后 best-effort 删除旧 audio，删除曲目时先停止试听再清理关联 score/audio/progress。
- 删除用户曲目时同时删除 score、绑定 audio 和该 song UUID 的三类练习记录；进度清理失败不回滚已完成的曲目删除。

## 练习 progress

`progress-v1.json` 是唯一练习事实文件。当前 schema 为 2，包含 `schemaVersion`、`songs`、`scoreMetadata`、`sessions` 三个数组；缺版本的旧文件仅在读取边界按 version 1 解码并在下次写入升级，未知版本 fail closed。

保存：

- song UUID、score revision、entry version token；
- immutable round configuration 与 resume point；
- source-measure facts、maturity、metric summaries、sample count、rubric version、evidence coverage；
- score metadata；
- session identity、开始/结算时间、本地练习日、checkpoint、window/active duration、termination。

不保存：

- SwiftUI 状态、cue、summary、hotspot、恢复地图、RealityKit entity；
- alignment、逐音 assessment evidence、target profile、`MusicalIssue`、coaching decision、before/after 关联；
- `PianoOutputMeasurementMetadata` 的原始测量、设备序列号、路由显示名；
- AI 内容、原始 MusicXML、逐帧音频/MIDI/手部数据。

progress、metadata、session mutation 在 actor 内读取磁盘最新文档，只更新自己的 concern；调用方不得整份覆盖。checkpoint 必须用 song identity、round generation 和 progress generation 防止旧任务回写。

## take 与诊断

- take 保存 source/capability/clock/calibration 和可重放 observation；MIDI 7/14-bit 投影只在回放或导出边界生成。
- target audio 因缺少可靠逐音 release/velocity 不进入 MIDI take。
- 诊断事件先进入系统日志，只有明确 exportable 的低频事件写入 JSONL；默认保留七个日历日，导出由用户触发。
- 任何导出文件不得包含绝对路径、原谱正文、逐音输入、音频样本、手部帧、AI prompt/正文、密钥或认证信息。

## 清理

重置用户数据时按需清理：

```text
Documents/SongLibrary/
Documents/TakeLibrary/
Documents/PracticeProgress/
Documents/Diagnostics/
Documents/piano-worldanchor-calibration.json
```

不要删除 App bundle 资源，也不要把测试 fixture 当作用户数据。
