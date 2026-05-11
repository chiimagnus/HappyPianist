# macOS App：LonelyPianist

这里是 macOS 主应用源码目录，负责把 MIDI 输入变成可见、可控、可回放的本地体验。

## 这层负责什么

- 监听 MIDI 设备
- 录制 take，并回放到内建 Sampler 或外部 MIDI 目的地

## 快速上手

1. 打开 `LonelyPianist.xcodeproj`
2. 选择 `LonelyPianist` scheme
3. 运行到 macOS 26.0+ 目标

## 没有实体 MIDI 键盘？

可以用虚拟 MIDI 键盘测试，例如 [MidiKeys](https://github.com/flit/MidiKeys)。
打开后，App 会自动识别为一个 MIDI source（若没有出现，重启 App 再试）。

> 不建议用 GarageBand 做外部广播测试，它的 MIDI 事件不会稳定广播给外部应用。

## 使用蓝牙 MIDI（BLE MIDI）

在 App 工具栏点击 `Bluetooth MIDI…`，在系统窗口里 Connect 你的钢琴/键盘即可。

如果系统弹出蓝牙权限提示，请选择允许；否则在：

System Settings → Privacy & Security → Bluetooth 中允许 `LonelyPianist`。

## 关联文档

- visionOS 端：[`../LonelyPianistAVP/README.md`](../LonelyPianistAVP/README.md)
- 仓库知识库：[`../.github/deepwiki/INDEX.md`](../.github/deepwiki/INDEX.md)
- 蓝牙 MIDI（系统连接方式）：[`Docs/macos-bluetooth-midi-setup.md`](Docs/macos-bluetooth-midi-setup.md)
