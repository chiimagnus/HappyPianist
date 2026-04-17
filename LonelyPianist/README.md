# macOS App：LonelyPianist

这里是 **macOS 主应用**的源码目录（SwiftUI + CoreMIDI + SwiftData）。

## 这个 App 做什么

- 监听 MIDI 输入（电子琴/MIDI 键盘）
- 把演奏事件映射为文本 / 快捷键 / 快捷指令（Shortcuts）等
- 与本机 Python 后端配合，实现 **Piano Dialogue（AI 钢琴对话）**

## 🤖 Piano Dialogue：在 App 中如何使用

前置：先把 Python 服务跑起来（见 `piano_dialogue_server/README.md`）。

1. 启动 `LonelyPianist`（主窗口直接显示）
2. 首次使用需要授予 **辅助功能权限**（否则无法开始监听）
3. 点击 `Start Listening`
4. 在侧边栏选择 `Dialogue`，点击 `Start Dialogue`
5. 弹一段，停顿（默认静默 2s + 踏板抬起）后触发 AI 回应
6. 回应会自动回放到你选择的 playback output，并保存为 take（Recorder 里可见）

回放期间的输入策略（可持久化，默认 B）：

- A Ignore：忽略你的输入
- B Interrupt：你一按键就打断 AI，立刻开始收集下一句（默认）
- C Queue：排队，AI 播完后再生成下一句

## 🎹 没有实体 MIDI 键盘？

没问题！你可以用虚拟 MIDI 键盘测试：

- 推荐 [MidiKeys](https://github.com/flit/MidiKeys)（开源免费）
- 打开 MidiKeys 后，在 App 中点击 `Refresh MIDI Sources` 即可识别

> 💡 避坑提示：不要用库乐队（GarageBand）测试 — 它的 MIDI 事件不会广播给外部应用。

## 运行与验收

本目录只维护与 macOS App 相关的使用与验收（本文件）。与 Python/AVP 相关的内容请看：

- Python 服务（Dialogue/OMR）：`piano_dialogue_server/README.md`
- AVP（AR Guide）：`LonelyPianistAVP/README.md`
