# BLE MIDI 协议分离（midi-protocol-separation）

目标：在输入边界把 **MIDI 1.0** 与 **MIDI 2.0** 完全分离，避免“把 MIDI2 隐式缩放到 7-bit 才能用”的语义补丁，保证 step advance 不会因为 velocity 量化/截断而卡住。

## 为什么必须分离

- **语义不同**：MIDI 1.0 的 Channel Voice 是 7-bit/14-bit 语义；MIDI 2.0 的 Channel Voice 具备更高精度（例如 velocity16、CC32、pressure32、pitchbend32）。
- **隐式缩放会引入逻辑耦合**：如果在输入侧把 MIDI2 压到 7-bit，再在上层用 `velocity > 0` 做有效性门槛，就会出现“按了很多次仍然过不了 step”的假阴性（特别是 BLE/mini 设备在 CoreMIDI 转换链路中出现值域变化时）。
- **根本修复方向**：step matcher 只依赖 note number + 时间窗（chord window），不依赖 velocity 门槛；MIDI2 的降精度只允许发生在明确边界（例如写入 take/phrase）。

## 当前实现（AVP）

- 输入源：`LonelyPianistAVP/Services/MIDI/BluetoothMIDIInputEventSourceService.swift`
  - 创建两个 input port：MIDI1（`MIDIProtocolID._1_0`）与 MIDI2（`MIDIProtocolID._2_0`）。
  - 连接 source 时传 `connRefCon`，回调里用 `srcConnRefCon` 反查 endpoint 身份（`uniqueID` / `name` / `sourceIndex`），用于归因与去重。
  - 按 endpoint 的 `kMIDIPropertyProtocolID` 选择订阅端口：同一 endpoint **禁止同时连接两个 port**（避免双投递与透明转换）。
  - 暴露两条流：`midi1EventsStream()` / `midi2EventsStream()`。
- 事件模型：
  - `LonelyPianistAVP/Models/MIDI/MIDI1InputEvent.swift`
  - `LonelyPianistAVP/Models/MIDI/MIDI2InputEvent.swift`
- step advance 消费侧：
  - `LonelyPianistAVP/ViewModels/PracticeSession/PracticeSessionViewModel+PracticeInput.swift`
  - **只要 noteOn 到达即可**（不再做 `velocity > 0` 过滤）；MIDI 1.0 的 `noteOn velocity==0 == noteOff` 仅在解码器内部处理。

## 实机验证（FP-30X BLE）

建议在真机运行（simulator 不覆盖 BLE MIDI）：

- 连接：系统蓝牙设备通常显示为 `FP-30X MIDI`（或类似名称）。
- 过滤日志（Console）：
  - `BluetoothMIDI` / `BluetoothMIDI-MIDI1` / `BluetoothMIDI-MIDI2`（输入侧与 summary）
  - `PracticeInput-StepAdvance`（step advance）
  - `PracticeInput-Recording`（take/phrase）
- 你应该能看到：
  - `Connected MIDI sources: ... protocolID=... subscribed=midi1|midi2 ... uniqueID=...`
  - 周期性 `MIDI delivery summary`，包含：
    - `eventListProtocols{...}`
    - `midi1Types{...} midi1Sources{...}`
    - `midi2Types{...} midi2Sources{...}`
    - `drops{...}`（协议不一致被丢弃的计数）
  - 对同一个 `debugEventID`：
    - `PracticeInput-StepAdvance` 的 matched/wrong/insufficient
    - `PracticeInput-Recording` 的 recording saw ...

判定“没有双投递”的一个简单方式：
- `midi1Sources{...}` 与 `midi2Sources{...}` 不应同时对同一个 uid/idx 持续增长；如果两者都增长，需要检查端口选择或 CoreMIDI 转换链路。

## 常见误区

- 把 MIDI2 velocity/CC 在输入侧先压到 7-bit：这会把高精度语义变成“看起来像 MIDI1”，导致上层把 velocity 当成可靠门槛，从而出现假阴性。
- 在 matcher 内做协议猜测：协议选择必须发生在输入边界（CoreMIDI UMP 解码处），matcher 只做语义层匹配。

