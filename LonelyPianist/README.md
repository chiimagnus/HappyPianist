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
打开后，在 App 中点 `Refresh MIDI Sources` 即可识别。

> 不建议用 GarageBand 做外部广播测试，它的 MIDI 事件不会稳定广播给外部应用。

## 关联文档

- visionOS 端：[`../LonelyPianistAVP/README.md`](../LonelyPianistAVP/README.md)
- 仓库知识库：[`../.github/deepwiki/INDEX.md`](../.github/deepwiki/INDEX.md)
