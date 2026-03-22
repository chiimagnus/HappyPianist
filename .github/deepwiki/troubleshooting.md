# 故障排查

## 症状索引

| 症状 | 可能范围 | 首查位置 | 快速判断 |
| --- | --- | --- | --- |
| 显示 `Listening MIDI` 但目标应用无输入 | 权限未授权 / 注入受限 | Runtime `Status` + 系统设置 | `hasAccessibilityPermission` 是否为 true |
| `MIDI Events: 0` 持续不变 | 无 MIDI Source / 源未连接 | Runtime `Sources` + Refresh | `connectedSourceNames` 是否为空 |
| Rec 后没有 Take | 录制期间无有效 note 事件 | `Recent Events` + Recorder 状态栏 | 是否出现 note on/off 日志 |
| Play 失败 | 音色库缺失 / 引擎启动失败 | `recorderStatusMessage` | 是否提示 sound bank / engine failed |
| CLI `render` 报错 | 输入路径/参数错误 | 终端 stderr + usage | 是否缺少 `--input`/`--output` |

## 第一现场信息

1. Runtime 页：`Status`、`Sources`、`MIDI Events`、`Pressed`、`Preview`。
2. Recent Events：查看最近 12 条状态与动作日志。
3. Recorder 状态栏：`recorderStatusMessage` + `Notes` + `Duration`。
4. CLI：错误输出与 usage 文本。

## 常见故障场景

### 场景 1：授权后仍未生效

- 现象：状态长期停在 `Waiting for Accessibility authorization...`。
- 可能原因：系统没有再次弹窗，或用户只打开了设置未实际勾选。
- 排查步骤：
  1. 手动进入系统设置 `隐私与安全性 > 辅助功能`。
  2. 确认 `PianoKey` 勾选状态。
  3. 切回应用触发 `didBecomeActive` 后刷新状态。
- 处理方式：必要时重新点击 `Grant Permission` 并重启应用。

### 场景 2：有 MIDI 输入但规则不触发

- 现象：事件计数增长，但无 Preview 输出。
- 可能原因：
  - 当前 active profile 无对应规则。
  - 和弦规则未满足“完全相等”匹配条件。
  - 旋律输入超出间隔窗口或冷却抑制。
- 排查步骤：
  1. 在 Mappings 页确认 active profile。
  2. 使用 Single Key 规则做最小验证。
  3. 查看 Recent Events 是否仅记录 MIDI 而无 Trigger。
- 处理方式：先用最小规则确认链路，再逐步恢复复杂规则。

## 调试入口与命令

| 入口 / 命令 | 位置 | 用途 | 备注 |
| --- | --- | --- | --- |
| `Refresh Sources` | Runtime/MenuBar | 重连 MIDI 来源 | 最常用恢复操作 |
| `Grant Permission` | Runtime/MenuBar | 触发授权流程 | 未授权时必查 |
| `xcodebuild ... build` | 仓库根目录 | 校验代码可构建 | 提交前建议执行 |
| `swift run --package-path Packages/PianoKeyCLI ... --json` | 仓库根目录 | CLI 可观测渲染结果 | 便于脚本诊断 |

## 恢复与回退

- 监听异常：Stop -> Start -> Refresh Sources。
- 规则异常：切回默认 profile（`Default QWERTY`）进行最小化验证。
- 录制异常：删除异常 take，重新录制。
- CLI 异常：先确认 `--input` 路径，再尝试指定 `--sound-bank`。

## 已知尖锐边界

1. CoreMIDI 可能接收到非 note 消息，服务默认忽略并仅记录一次提示。
2. 播放 seek 是异步重启，连续拖动可能触发高频任务取消/重建。
3. App 是菜单栏工具模式时，Dock 可见性取决于显示模式与窗口状态。

## 示例片段

```swift
// PianoKey/Services/MIDI/CoreMIDIInputService.swift
guard status == .noteOn || status == .noteOff else {
    if !didLogNonNoteMessage {
        logger.info("Receiving MIDI data, but no note-on/off yet")
        didLogNonNoteMessage = true
    }
    return
}
```

```swift
// Packages/PianoKeyCLI/Sources/PianoKeyCLI/main.swift
case .missingRequiredOption(let option):
    return "Missing required option '\(option)'."
```

## Coverage Gaps（如有）

- 尚无统一 crash dump 采集方案，复杂现场需依赖本地复现。

## 来源引用（Source References）

- `README.md`
- `PianoKey/ViewModels/PianoKeyViewModel.swift`
- `PianoKey/Views/Runtime/StatusSectionView.swift`
- `PianoKey/Views/Runtime/RecentEventSectionView.swift`
- `PianoKey/Services/MIDI/CoreMIDIInputService.swift`
- `PianoKey/Services/Mapping/DefaultMappingEngine.swift`
- `PianoKey/Services/Playback/AVSamplerMIDIPlaybackService.swift`
- `PianoKey/Services/System/AccessibilityPermissionService.swift`
- `Packages/PianoKeyCLI/Sources/PianoKeyCLI/main.swift`
