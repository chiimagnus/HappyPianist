# 运维（本地运行视角）

## 运行状态面板

| 状态信号 | 位置 | 代表含义 | 常见动作 |
| --- | --- | --- | --- |
| `connectionDescription` | Runtime / MenuBar | MIDI 连接状态 | Start/Stop/Refresh |
| `statusMessage` | Runtime / MenuBar | 全局运行状态 | 权限与连接排查 |
| `midiEventCount` | Runtime | 事件吞吐是否增长 | 判断链路是否活着 |
| `recorderStatusMessage` | Recorder 状态栏 | 录制/回放状态 | Rec/Play/Stop/Seek |

## 日常运维动作

| 场景 | 操作 | 期望结果 |
| --- | --- | --- |
| 新设备接入 | Refresh Sources | `connectedSourceNames` 更新 |
| 授权恢复 | Grant Permission + 系统设置确认 | `hasAccessibilityPermission = true` |
| 状态重置 | Stop Listening -> Start Listening | `connectionState` 恢复 |
| Recorder 清理 | 删除异常 Take | 列表与选中态一致 |

## 运行观察指标（本地）

- 输入链路：`midiEventCount` 是否持续增长。
- 执行链路：Recent Events 是否出现 trigger 记录。
- 存储链路：重启后 profile/takes 是否恢复。
- 回放链路：playhead 是否推进并触发 finished 状态。

## 故障处理优先级

1. 先确认权限。
2. 再确认 MIDI Source。
3. 再确认规则是否命中。
4. 最后检查回放/存储层。

## 维护窗口建议

- 变更输入注入与权限流程时，优先在可回滚分支验证。
- 大规模规则结构变更前，先导出（或备份）现有 profile/take 数据。

## 示例片段

```swift
// LonelyPianist/ViewModels/LonelyPianistViewModel.swift
func refreshMIDISources() {
    do {
        try midiInputService.refreshSources()
        statusMessage = "MIDI sources refreshed"
    } catch {
        statusMessage = "Refresh failed: \(error.localizedDescription)"
    }
}
```

```swift
// LonelyPianist/Views/Runtime/StatusSectionView.swift
Text("Status: \(viewModel.statusMessage)")
Text("Sources: \(sourceNamesText)")
Text("MIDI Events: \(viewModel.midiEventCount)")
```

## Coverage Gaps（如有）

- 未发现集中日志落盘策略与运维仪表盘能力。

## 来源引用（Source References）

- `LonelyPianist/ViewModels/LonelyPianistViewModel.swift`
- `LonelyPianist/Views/Runtime/StatusSectionView.swift`
- `LonelyPianist/Views/Runtime/RecentEventSectionView.swift`
- `LonelyPianist/Views/MenuBar/MenuBarPanelView.swift`
- `LonelyPianist/Views/Recording/RecorderStatusBarView.swift`
- `LonelyPianist/Services/MIDI/CoreMIDIInputService.swift`
- `README.md`
