# AVP Library

## 范围
曲库页覆盖 seed、导入、删除、音频绑定、试听和索引一致性。

## 关键对象
| 对象 | 职责 |
| --- | --- |
| `SongLibraryViewModel` | 曲库编排 |
| `SongLibrarySeeder` | 启动 seed / backfill |
| `SongLibraryIndexStore` | 索引读写 |
| `SongFileStore` | 曲谱文件复制 / 删除 |
| `AudioImportService` | 音频文件复制 |
| `SongAudioPlaybackStateController` | 试听按钮状态 |

## 行为
- 首次启动若索引为空，会注入 bundled seed。
- 已有 seed 但缺音频时，会补齐音频。
- 导入顺序是先复制文件，再提交索引。
- 删除顺序是先删索引，再删文件。
- 试听只接受已绑定音频的条目。

## 数据约束
| 约束 | 说明 |
| --- | --- |
| 文件名 | 加时间戳前缀，避免覆盖 |
| 类型 | MusicXML + mp3 / m4a |
| 索引 | `index.json` 原子写入 |
| 播放状态 | `currentListeningEntryID` + `isCurrentListeningPlaying` |

## 调试抓手
- `errorMessage`
- `currentListeningEntryID`
- `isCurrentListeningPlaying`
- `index.entries`


## Coverage Gaps
- 长期清理任务没有自动化后台作业，孤儿文件仍可能累积。

