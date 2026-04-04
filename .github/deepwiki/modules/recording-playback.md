# 模块：录制与回放（Recorder / Playback）

## 职责与边界

- 负责 MIDI 事件录制为 Take、Take 管理与钢琴音色回放。
- 负责 Recorder UI（Transport、Piano Roll、状态栏）。
- 不负责映射动作执行（text/keyCombo/shortcut）。

## 目录范围

| 路径 | 角色 | 备注 |
| --- | --- | --- |
| `LonelyPianist/Services/Recording/DefaultRecordingService.swift` | 录制核心 | note on/off -> RecordedNote |
| `LonelyPianist/Services/Playback/RoutedMIDIPlaybackService.swift` | 回放路由 | built-in sampler / 外部 MIDI destination |
| `LonelyPianist/Services/Playback/AVSamplerMIDIPlaybackService.swift` | 回放实现（本机） | take -> scheduled events -> sampler |
| `LonelyPianist/Services/Playback/CoreMIDIOutputMIDIPlaybackService.swift` | 回放实现（外设） | take -> scheduled events -> CoreMIDI out |
| `LonelyPianist/Services/Storage/SwiftDataRecordingTakeRepository.swift` | Take 持久化 | 保存/删除/重命名 |
| `LonelyPianist/Views/Recording/*` | Recorder UI | Transport/Piano Roll/Status |

## 入口点与生命周期

| 入口 / 类型 | 位置 | 何时触发 | 结果 |
| --- | --- | --- | --- |
| `startRecordingTake()` | `LonelyPianistViewModel.swift` | 用户点 Rec | `recorderMode = .recording` |
| `stopTransport()`（recording 分支） | `LonelyPianistViewModel.swift` | 点 Stop | 生成并保存 Take |
| `playSelectedTake()` | `LonelyPianistViewModel.swift` | 点 Play | 启动回放与 playhead 时钟 |
| `seekPlayback(to:)` | `LonelyPianistViewModel.swift` | 拖动 slider | 异步重启播放到新 offset |

## 关键文件

| 文件 | 用途 | 为什么值得看 |
| --- | --- | --- |
| `DefaultRecordingService.swift` | 录制时值计算 | stop 自动闭合逻辑在此 |
| `RoutedMIDIPlaybackService.swift` | 回放输出选择 | output 列表与路由逻辑在此 |
| `AVSamplerMIDIPlaybackService.swift` | 本机音频回放 | noteOn/noteOff 时间排序关键 |
| `CoreMIDIOutputMIDIPlaybackService.swift` | 外设 MIDI 回放 | 调度与 stop-all-notes 在此 |
| `SwiftDataRecordingTakeRepository.swift` | 存储映射 | 数据恢复与列表排序逻辑 |
| `RecorderTransportBarView.swift` | 交互入口 | Rec/Play/Stop/Seek/Output/Rename/Delete 全在此 |
| `PianoRollView.swift` | 可视化 | 调试音高与时值非常直观 |

## 上下游依赖

| 方向 | 对象 | 关系 | 影响 |
| --- | --- | --- | --- |
| 上游 | MIDI 事件流 | 录制模式下 append 事件 | 影响 take 内容 |
| 下游 | Recording Repository | 保存与读取 take | 影响重启恢复 |
| 下游 | Playback Service | 播放/停止/seek | 影响用户试听体验 |

## 对外接口与契约

| 接口 / 类型 | 位置 | 调用方 | 含义 |
| --- | --- | --- | --- |
| `RecordingServiceProtocol` | `Services/Protocols` | ViewModel | 录制状态与 stop 产物契约 |
| `MIDIPlaybackServiceProtocol` | `Services/Protocols` | ViewModel | 播放与完成通知契约 |
| `RecordingTakeRepositoryProtocol` | `Services/Protocols` | ViewModel | Take 持久化接口 |

## 数据契约、状态与存储

- `RecordingTake`：`id/name/durationSec/notes[]`。
- `RecordedNote`：`note/velocity/channel/startOffsetSec/durationSec`。
- SwiftData：`RecordingTakeEntity` 与 `RecordedNoteEntity`（cascade 删除）。

## 配置与功能开关

- Recorder 没有独立持久化配置项，主要受 ViewModel 状态驱动：`recorderMode`, `selectedTakeID`, `playheadSec`。

## 正常路径与边界情况

1. 录制中再次收到同 note on：先闭合旧 note 再开启新 note。
2. stop 时未 noteOff 的 open note：按 stop 时间自动闭合。
3. 回放事件排序：同时间点 noteOff 优先于 noteOn，减少粘连。

## 扩展点与修改热点

- 新录制字段（如 pedal、tempo）需要同步 domain/entity/repository/UI。
- 回放引擎替换需保证 `onPlaybackFinished` 与 `isPlaying` 语义兼容。

## 测试与调试

- 已有 `DefaultRecordingServiceTests` 覆盖基础录制时值计算。
- `LonelyPianistViewModelRecorderStateTests` 验证播放不触发注入。
- 调试优先看 Recorder 状态栏与 Piano Roll 形态是否符合预期。

## 示例片段

```swift
// DefaultRecordingService.swift
for (key, openNote) in openNotes {
    appendRecordedNote(
        note: key.note,
        velocity: openNote.velocity,
        channel: key.channel,
        startAt: openNote.startedAt,
        endAt: stopAt,
        recordingStartedAt: startedAt
    )
}
```

```swift
// AVSamplerMIDIPlaybackService.swift
case (.noteOff, .noteOn):
    return true
```

## Coverage Gaps（如有）

- 目前未见针对 seek 高频拖动的压力测试。
- 未见外部 MIDI 文件导入与多轨回放能力。

## 来源引用（Source References）

- `LonelyPianist/ViewModels/LonelyPianistViewModel.swift`
- `LonelyPianist/Services/Recording/DefaultRecordingService.swift`
- `LonelyPianist/Services/Playback/RoutedMIDIPlaybackService.swift`
- `LonelyPianist/Services/Playback/AVSamplerMIDIPlaybackService.swift`
- `LonelyPianist/Services/Playback/CoreMIDIOutputMIDIPlaybackService.swift`
- `LonelyPianist/Services/Storage/SwiftDataRecordingTakeRepository.swift`
- `LonelyPianist/Models/Recording/RecordingTake.swift`
- `LonelyPianist/Models/Recording/RecordedNote.swift`
- `LonelyPianist/Models/Storage/RecordingTakeEntity.swift`
- `LonelyPianist/Models/Storage/RecordedNoteEntity.swift`
- `LonelyPianist/Views/Recording/RecorderTransportBarView.swift`
- `LonelyPianist/Views/Recording/PianoRollView.swift`
- `LonelyPianistTests/Recording/DefaultRecordingServiceTests.swift`
