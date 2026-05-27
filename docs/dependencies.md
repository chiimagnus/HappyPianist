# 依赖

## 平台依赖

| 运行面 | 主要 Apple framework | 用途 |
| --- | --- | --- |
| macOS recorder | SwiftUI、SwiftData、CoreMIDI、AVFoundation、CoreAudioKit | UI、take 存储、MIDI 输入/输出、sampler 回放、Bluetooth MIDI 面板。 |
| visionOS app | SwiftUI、RealityKit、ARKit、CoreMIDI、AVFoundation、CoreAudioKit、UniformTypeIdentifiers | 窗口/沉浸空间、空间 overlay、hand/world/plane tracking、BLE MIDI、音频识别与回放、文件导入。 |
| Tests | Swift Testing / XCTest project integration | macOS 与 AVP 的本地测试。 |

当前代码使用 SwiftUI Observation（`@Observable` / `@Bindable`）。新增状态对象时不要退回 `ObservableObject` / `@Published`。

## Python

当前仓库的 `python_backend/` 仅保留 shared 工具与脚手架，不内置可运行服务，因此没有强制 Python 依赖。

## 资源依赖

| 资源 | 当前状态 | 使用方 |
| --- | --- | --- |
| `LonelyPianistAVP/Resources/Audio/SoundFonts/SalC5Light2.sf2` | 仓库默认不内置 | AVP sampler 回放。 |
| `LonelyPianistAVP/Resources/Fonts/Bravura.otf` | 在 app bundle 中声明 | 谱面符号。 |
| Bundled MusicXML | 由 `BundledSongLibraryProvider` 扫描 | AVP 曲库。 |
| CoreML 模型文件 | 不入库 | `AIDuetPerformanceRNN.mlpackage` / `.mlmodelc`（由开发者本地加入 Xcode target）。 |

## 依赖边界

- macOS recorder 不依赖 Python 服务。
- AVP AI 即兴默认使用本地 CoreML / 本地 rule（无需电脑端服务）。
- `Packages/RealityKitContent/` 与 `Packages/ImprovEngines/` 是仓库内的 SwiftPM 包；若只关注主 app 逻辑，文档不应把它们作为唯一入口。
