# 项目概览

HappyPianist 包含空间练习的 visionOS App、独立沙盒的 macOS MusicXML/MIDI App、共享 Swift 核心、RealityKit 内容包，以及可选的 Mac 侧 Aria v2 服务。源码位置、符号和调用关系以 CodeGraph 为准；本文档只保留代码图无法表达的边界。

## 运行边界

| 单元 | 责任 |
| --- | --- |
| `HappyPianistAVP` / Tests | 曲库、准备、练习、录制、AI 对弹和沉浸空间。 |
| `HappyPianistMac` / Tests | 2D 曲库、系统可见 MIDI 端点和 MIDI-only 练习。 |
| `Packages/HappyPianistCore` | Diagnostics、MusicXML、MIDI、Practice、Notation、Library，以及平台中性 SwiftUI 曲库表现 `LibraryPresentation` 的公开产品。 |
| `Packages/RealityKitContent` | Reality Composer Pro 资产和 bundle。 |
| `python_backend/aria_server` | 可选的 Bonjour + HTTP/WS Aria v2 后端。 |

两个 App host 有各自的 composition root 和 App Sandbox；它们只共享 core 的公开产品，不共享视图、平台 adapter 或 Documents container。

## 导航

| 问题 | 文档 |
| --- | --- |
| 依赖方向与不变量 | [architecture.md](architecture.md) |
| 曲谱、练习、输入、进度与 AI 的事实流 | [data-flow.md](data-flow.md) |
| 产品能力可作何种表述 | [piano-performance-quality.md](piano-performance-quality.md) |
| 工程设置、权限与可选服务 | [configuration.md](configuration.md) |
| 持久化与隐私边界 | [storage.md](storage.md) |
| 自动化、真机与人工证据 | [testing.md](testing.md) |

正式练习只从 MusicXML（`.musicxml`、`.xml`、`.mxl`）准备；输入可来自麦克风、蓝牙 MIDI 或空间虚拟钢琴。专业能力状态由[质量边界](piano-performance-quality.md)的证据门决定，不能从实现或 Simulator 自动化单独推导。
