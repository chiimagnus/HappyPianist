# macOS Recorder

## 范围
Recorder 页覆盖 take 录制、MIDI 导入、take 回放、seek、重命名和删除。

## 关键对象
| 对象 | 职责 |
| --- | --- |
| `DefaultRecordingService` | 把 note on/off 合成 `RecordingTake` |
| `RecordingTakeRepository` | take 的持久化 |
| `MIDIFileImporter` | 导入 MIDI 文件为 notes |
| `RoutedMIDIPlaybackService` | 播放 take |

## 录制规则
| 规则 | 含义 |
| --- | --- |
| 开启录制时清空旧状态 | 避免串 take |
| note off 缺失 | stop 时按 stop 时刻补全 |
| duration 最短值 | 保证 note 至少持续 0.01 秒 |
| 时间戳早于开始 | fallback 到当前 clock |

## 播放和导入
- `playSelectedTake()` 会从当前 playhead 开始播放。
- `seekPlayback(to:)` 在播放中会延迟 50ms 再重启播放。
- `importMIDIFile(from:mode:)` 支持 `all` 和 `pianoOnly`。
- `setPlaybackOutput(id:)` 可切换 built-in sampler 或外部 MIDI 目的地。

## 调试抓手
- `recorderMode` / `recorderStatusMessage`
- `takes` / `selectedTakeID`
- `playheadSec`
- `playbackOutputs` / `selectedPlaybackOutputID`


## Coverage Gaps
- 外部 MIDI 目的地的实际设备兼容性仍依赖本地环境验证。

