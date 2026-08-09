# 存储与隐私

每个 App host 只读写自己的 sandbox。曲库导入后只保留 sandbox 副本、相对文件名与 fingerprint；不保存外部 URL、security-scoped bookmark 或绝对路径。

## 持久化边界

| 数据 | 位置 | 保留内容 |
| --- | --- | --- |
| 曲库 | `Documents/SongLibrary/` | MusicXML、副本索引、可选曲目音频。 |
| 进度 | `Documents/PracticeProgress/` | song/revision、不可变 round 配置、source-measure 聚合事实、resume/checkpoint、metadata、session facts。 |
| Take | `Documents/TakeLibrary/` | 可重放 observation 及其 capability、clock、calibration。 |
| 诊断 | `Documents/Diagnostics/` | 仅 exportable 的低频结构化事件，默认七个日历日。 |
| 空间校准 | `Documents/piano-worldanchor-calibration.json` | 校准数据。 |

文件版本未知或损坏时 fail closed；所有写入使用 actor/原子替换。progress、metadata 与 session 必须分别读取磁盘最新文档后更新自己的 concern，不能整份覆盖。重置只删除对应 Documents 数据，绝不删除 bundle 资源或 test fixture。

## 不得持久化

- SwiftUI/RealityKit 状态、cue、summary、恢复地图、键面/手部渲染；
- alignment、逐音 evidence、target profile、`MusicalIssue`、coaching decision 与 before/after 关联；
- 原始 MusicXML、音频、MIDI、手部帧、设备序列号、route 显示名、导出目的地；
- AI prompt/正文、密钥、认证信息和绝对路径。

take 回放或 MIDI 导出仅在用户动作边界生成需要的投影；导出目标 URL 不回写 store。诊断先进入系统日志，导出的字段仍遵循上述脱敏规则。
