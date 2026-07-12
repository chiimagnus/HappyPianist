# 依赖

## Apple 平台

| 依赖 | 用途 |
| --- | --- |
| SwiftUI + Observation | 窗口、设置、曲库、练习 UI 与状态绑定。 |
| RealityKit | 沉浸空间、琴键高亮、虚拟钢琴和恢复效果。 |
| ARKit | world、hand 与 plane tracking。 |
| AVFoundation | sampler、sequencer、音频播放与麦克风识别。 |
| CoreMIDI + CoreAudioKit | Bluetooth MIDI 输入、外部 MIDI 输出与系统连接面板。 |
| CoreML | 可选的本地 Performance RNN 后端。 |
| CryptoKit | bundled 曲目稳定 UUID 与曲谱 digest。 |
| UniformTypeIdentifiers | MusicXML、MXL、音频与 MIDI 文件选择。 |

App target 为 visionOS 26.0、Swift 6.0。测试使用 Swift Testing，并通过 Xcode test target 集成。

## SwiftPM

| 包 | 来源 | 用途 |
| --- | --- | --- |
| `RealityKitContent` | `Packages/RealityKitContent/` | Reality Composer Pro 内容 bundle。 |
| `ZIPFoundation` 0.9.20 | GitHub remote package | 解包 `.mxl`。 |

锁定版本见 `HappyPianist.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`。

## Python（可选）

`python_backend/` 不是 AVP App 的必需依赖，只在选择 Aria v2 网络后端时运行。

- Python 3.11+
- `uv`
- Apple silicon 上的 MLX/Aria 依赖
- `python_backend/aria/hf/model-demo.safetensors`
- Bonjour、HTTP 与 WebSocket 网络环境

服务工程：`python_backend/aria_server/`。入口与 smoketest 位于 `python_backend/scripts/`。

## 外部资源

源码归档不包含：

| 资源 | 代码期望名称 | 用途 |
| --- | --- | --- |
| Bravura 字体 | `Bravura.otf` | 五线谱符号。 |
| Salamander SoundFont | `SalC5Light2.sf2` | AVP 本地 sampler。 |
| Performance RNN 模型 | `AIDuetPerformanceRNN.mlpackage` 或 `.mlmodelc` | 本地 CoreML 对弹。 |
| Aria 权重 | `python_backend/aria/hf/model-demo.safetensors` | Mac 侧 Aria v2 推理。 |

资源是否可用以实际文件和 App bundle 为准，不以 plist 声明或代码常量为准。

## 依赖边界

- 正常练习不依赖 Python 服务。
- 本地规则 AI 不依赖 CoreML 模型或 Python。
- MXL 导入依赖 ZIPFoundation；普通 MusicXML 不依赖 Python。
- Apple framework 行为只能在 Xcode/Simulator/设备环境中完成最终验证。
