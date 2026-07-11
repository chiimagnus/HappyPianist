# 依赖

## 平台依赖

| 运行面 | 主要 Apple framework | 用途 |
| --- | --- | --- |
| macOS recorder | SwiftUI、SwiftData、CoreMIDI、AVFoundation、CoreAudioKit | UI、take 存储、MIDI 输入/输出、sampler 回放、Bluetooth MIDI 面板。 |
| visionOS app | SwiftUI、RealityKit、ARKit、CoreMIDI、AVFoundation、CoreAudioKit、UniformTypeIdentifiers | 窗口/沉浸空间、空间 overlay、hand/world/plane tracking、BLE MIDI、音频识别与回放、文件导入。 |
| Tests | Swift Testing / XCTest project integration | macOS 与 AVP 的本地测试。 |

当前代码使用 SwiftUI Observation（`@Observable` / `@Bindable`）。新增状态对象时不要退回 `ObservableObject` / `@Published`。

## Python

`python_backend/` 是可选工作区：

- 默认情况下（仅使用 AVP 本地后端）：不需要 Python。
- 若要在 AVP 端使用 **网络后端（Aria v2）**：需要在 Mac 上运行 `python_backend/aria_server/`（Bonjour + HTTP/WS）。

建议环境：

- Apple silicon（MLX 推理）
- Python 3.11+
- `uv` 管理依赖

注意：Aria demo checkpoint 体积较大（默认路径 `python_backend/aria/hf/model-demo.safetensors`），不会随仓库分发。

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
- `Packages/RealityKitContent/` 是仓库内的 SwiftPM 包；AI 即兴实现内嵌在 AVP target。
