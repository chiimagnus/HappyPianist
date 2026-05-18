# Docs 索引（LonelyPianist）

`docs/` 的唯一入口：按主题导航，下钻到模块页。

## 全局页面
- [overview.md](overview.md)
- [architecture.md](architecture.md)
- [data-flow.md](data-flow.md)
- [dependencies.md](dependencies.md)
- [configuration.md](configuration.md)
- [storage.md](storage.md)
- [workflow.md](workflow.md)
- [troubleshooting.md](troubleshooting.md)
- [glossary.md](glossary.md)
- [Fallbacks.md](Fallbacks.md)
- [GENERATION.md](GENERATION.md)

## 模块页

### macOS 主应用
- [modules/lonelypianist-macos.md](modules/lonelypianist-macos.md)
- [modules/lonelypianist-macos-runtime.md](modules/lonelypianist-macos-runtime.md)
- [modules/lonelypianist-macos-mapping.md](modules/lonelypianist-macos-mapping.md)
- [modules/lonelypianist-macos-recording.md](modules/lonelypianist-macos-recording.md)
- [modules/lonelypianist-macos-dialogue.md](modules/lonelypianist-macos-dialogue.md)

### visionOS 原型
- [modules/lonelypianist-avp.md](modules/lonelypianist-avp.md)
- [modules/lonelypianist-avp-piano-modes.md](modules/lonelypianist-avp-piano-modes.md)
- [modules/lonelypianist-avp-library.md](modules/lonelypianist-avp-library.md)
- [modules/lonelypianist-avp-calibration.md](modules/lonelypianist-avp-calibration.md)
- [modules/lonelypianist-avp-musicxml.md](modules/lonelypianist-avp-musicxml.md)
- [modules/lonelypianist-avp-tracking.md](modules/lonelypianist-avp-tracking.md)
- [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md)
- [modules/lonelypianist-avp-practice-audio.md](modules/lonelypianist-avp-practice-audio.md)

### Python 对话服务
- [modules/piano-dialogue-server.md](modules/piano-dialogue-server.md)
- [modules/piano-dialogue-server-protocol.md](modules/piano-dialogue-server-protocol.md)
- [modules/piano-dialogue-server-inference.md](modules/piano-dialogue-server-inference.md)
- [modules/piano-dialogue-server-debug.md](modules/piano-dialogue-server-debug.md)

## 按问题导航
- **想先理解产品在做什么**：先看 `overview.md`。
- **要改 macOS 监听 / 映射 / 录音 / 对话**：看 `modules/lonelypianist-macos.md`，再下钻对应子页。
- **要改 AVP 导入 / 校准 / 练习 / MusicXML**：看 `modules/lonelypianist-avp.md`，再下钻对应子页。
- **要改 MusicXML 双 part 归一化（左手音符丢失）**：看 `modules/lonelypianist-avp-musicxml.md` 的「钢琴双 part 归一化」章节。
- **要改五线谱渲染（stems/beams/flags/SMuFL）**：看 `modules/lonelypianist-avp-practice.md` 的「双谱表五线谱」章节。
- **要改 AR 引导贴皮高亮**：看 `modules/lonelypianist-avp-practice.md` 和 `PianoGuideOverlayController`。
- **要改虚拟钢琴**：看 `modules/lonelypianist-avp-practice.md` 的「虚拟钢琴模式」章节，涉及放置状态机、按键检测、3D 渲染和实时发声。
- **要改蓝牙 MIDI 模式 / Take 录制**：看 `modules/lonelypianist-avp.md` 的「Bluetooth MIDI（BLE）」章节和 `modules/lonelypianist-avp-practice.md` 的三种钢琴模式表。
- **要改 Python 协议或采样逻辑**：看 `modules/piano-dialogue-server.md` 与 `modules/piano-dialogue-server-inference.md`。
- **要运行测试 / 本地验证**：见 `workflow.md`。
- **要手动格式化**：见 `configuration.md`（`.swiftformat`）。
- **遇到运行异常**：从 `troubleshooting.md` 开始。
