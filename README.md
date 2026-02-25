# PianoKey

用 MIDI 键盘控制 Mac 输入的菜单栏应用。

## 你可以做什么

- 把单个音符映射成文本输入
- 用和弦触发组合键（如 `cmd+c`）
- 用旋律触发文本、组合键或快捷指令
- 用力度阈值区分不同输出
- 保存多套 Profile，随时切换
- 录制 MIDI 演奏并以钢琴音色回放（Recorder）

## 快速上手

1. 启动 PianoKey。
2. 在菜单栏打开应用面板。
3. 点击 `Grant Permission` 完成辅助功能授权（首次必做）。
4. 点击 `Start Listening` 开始监听 MIDI。
5. 点击 `Open PianoKey` 打开主窗口，在侧边栏选择 `Mappings`，在 `Profiles / Rules` 中设置你的映射。
6. 回到任意可输入文本的应用，弹琴验证输出。

> 说明：PianoKey 默认不显示在 Dock，仅在菜单栏中提供入口。

## Recorder（录制与播放）

1. 先点击 `Start Listening`，确认有 MIDI 输入。
2. 点击 `Open PianoKey` 打开主窗口，在侧边栏选择 `Recorder`（或菜单栏点 `Open Recorder`）。
3. 点击 `Rec` 开始录制，演奏后点击 `Stop` 结束并生成新 Take。
4. 在左侧 Library 选择 Take，点击 `Play` 回放，点击 `Stop` 可立即停止。
5. 重新打开应用后，已保存的 Take 会自动恢复并可继续回放。

## 权限说明（必须）

PianoKey 通过系统输入注入发送按键，必须开启 macOS 的 `辅助功能 (Accessibility)` 权限。

- 点击 `Grant Permission` 后，会触发系统授权请求。
- 如果没有看到弹窗，应用会引导你打开：
  `系统设置 > 隐私与安全性 > 辅助功能`
- 在列表里勾选 `PianoKey` 后，返回应用即可生效。

## 常见问题

### 1) 点击授权后没有弹窗

这是 macOS 常见行为：如果你之前拒绝过，系统可能不再重复弹窗。请直接去系统设置手动勾选 `PianoKey`。

### 2) 状态一直是 `Waiting for Accessibility authorization...`

通常是系统权限刚变更但应用还在等待刷新。现在应用会自动轮询状态；若仍未更新，切回应用窗口或重新点击一次 `Grant Permission`。

### 3) 显示 `Listening MIDI` 但 `MIDI Events: 0`

请按顺序检查：

1. `Sources` 是否为空；为空时先点 `Refresh Sources`。
2. MIDI 设备或虚拟总线（如 IAC）是否在线。
3. 你的测试软件是否真的在输出 `note on/off` 事件。

### 4) 有 MIDI 事件，但目标应用没有输入

通常是辅助功能权限未正确生效，或目标应用处于受限输入场景（安全输入等）。先确认权限，再换普通文本输入框测试。

## 无实体琴测试

推荐使用 [**MidiKeys**](https://github.com/flit/MidiKeys)（开源免费，支持 Apple Silicon）作为虚拟 MIDI 键盘：

1. 下载并打开 MidiKeys。
2. 在 PianoKey 点击 `Start Listening`，再点 `Refresh Sources` → 确认 Sources 中出现 MidiKeys。
3. 在 MidiKeys 窗口按电脑键盘（A S D F 那一排对应白键）。
4. 观察 `MIDI Events`、`Pressed`、`Preview` 是否变化。

> ⚠️ **不要用库乐队（GarageBand）做测试源。** 库乐队的"音乐打字键盘"事件是内部消费的，不会通过其虚拟输出端口广播给外部应用。

## 已知限制

- 必须授予辅助功能权限后，跨应用输入才会生效。
- `shortcut` 动作依赖系统中已存在的同名快捷指令。
- 在部分系统受限输入场景下，事件可能被拦截。
- Recorder 当前为 MVP：仅固定钢琴音色、仅支持播放/查看，不支持编辑 Piano Roll。
- 不支持导入外部 `.mid` 文件或多轨/多乐器。
- 回放仅发声，不会触发文本注入、组合键或快捷指令。
