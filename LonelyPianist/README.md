# LonelyPianist macOS

这是 macOS MIDI recorder target。它负责监听 MIDI 输入、录制 take、导入 MIDI 文件，并回放到内建 sampler 或外部 MIDI destination。

## 当前边界

- 支持 MIDI 监听、record/stop、take 列表、rename/delete、MIDI 文件导入、seek/playback。
- 支持通过 app 打开系统 Bluetooth MIDI 面板。
- 不包含 mapping engine、keyboard injection 或 Python Dialogue client。

## 没有实体 MIDI 键盘？

可以用虚拟 MIDI 键盘测试，例如 [MidiKeys](https://github.com/flit/MidiKeys)。
打开后，App 会自动识别为一个 MIDI source（若没有出现，重启 App 再试）。

> 不建议用 GarageBand 做外部广播测试，它的 MIDI 事件不会稳定广播给外部应用。
