# 项目概览

HappyPianist 由 visionOS host、共享 Swift 核心、RealityKit 资产和可选 Aria v2 服务组成。源码位置、符号和调用关系以 CodeGraph 为准；AVP host 负责 composition root 与 App Sandbox，核心包不反向依赖 host。

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
