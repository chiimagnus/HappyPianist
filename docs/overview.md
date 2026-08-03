# 项目概览

HappyPianist 包含空间练习的 visionOS App，以及独立、沙盒化的 macOS MusicXML/MIDI 练习 App；仓库还包含测试、RealityKit 内容包和可选的 Mac 侧 Aria v2 Python 服务。

源码目录、符号定义和调用关系以 CodeGraph 为准；本知识库只保留代码图无法表达的产品意图、数据契约、运行边界与验证规则。

## 运行单元

| 运行单元 | 入口 | 作用 |
| --- | --- | --- |
| visionOS App | `HappyPianistAVP/` | 准备、曲库、练习、录制、AI 对弹与沉浸空间。 |
| visionOS Tests | `HappyPianistAVPTests/` | MusicXML、练习、输入、回放、反馈、窗口与服务测试。 |
| macOS App | `HappyPianistMac/` | 2D 曲库、系统可见 MIDI 端点和 MIDI-only 练习；不包含空间、音频识别或 AI。 |
| macOS Tests | `HappyPianistMacTests/` | macOS host、曲库、端点与练习流程测试。 |
| 共享 Swift 包 | `Packages/HappyPianistCore/` | 可复用的 Diagnostics、MusicXML 与 MIDI 低层模块；App 通过显式产品依赖使用它。 |
| RealityKit 内容包 | `Packages/RealityKitContent/` | Reality Composer Pro 资产与 bundle。 |
| Aria v2 服务（可选） | `python_backend/aria_server/` | Bonjour + HTTP/WS 网络即兴后端。 |

Xcode 工程包含隔离的 `HappyPianistAVP` / `HappyPianistAVPTests` 与 `HappyPianistMac` / `HappyPianistMacTests` target。两个 host 不共享 App container、视图或平台服务，只消费 [共享核心模块](modules/shared-core.md) 的公开产品；macOS host 边界见 [macOS App](modules/macos-app.md)。

## 按问题导航

| 想了解什么 | 文档 |
| --- | --- |
| 模块、依赖方向、运行时边界和危险修改区 | [architecture.md](architecture.md) |
| 共享包的产品边界与依赖图 | [modules/shared-core.md](modules/shared-core.md) |
| MusicXML、输入、练习、反馈、录制与 AI 的数据流 | [data-flow.md](data-flow.md) |
| 曲谱真值、参考演奏、输入证据、演奏评价、虚拟指导与专业验收路线 | [piano-performance-quality.md](piano-performance-quality.md) |
| Xcode、权限、依赖、资源、设置与可选服务 | [configuration.md](configuration.md) |
| Documents 目录、JSON、曲库、进度与诊断文件 | [storage.md](storage.md) |
| 日常 smoke、Simulator、真机、盲评与 evidence | [testing.md](testing.md) |
| 专业能力的通过条件与 pending / blocked 语义 | [piano-performance-quality.md](piano-performance-quality.md) |

## 产品主流程

```text
进入曲库并导入 MusicXML
-> 从左上角“选择钢琴”打开 pushed 准备窗口
-> 完成校准或虚拟琴放置并返回曲库
-> 选择曲目、查看右侧只读事实并点击主内容中的唯一“开始练习”按钮
-> 练习窗口准备曲谱并恢复精确版本的进度
-> 演奏、判定并保存小节事实
-> 完成本轮后生成 capability-aware assessment 与一个 coaching action
-> 接受或跳过建议，再进入下一轮
-> 查看即时反馈、总结和恢复地图
```

练习输入支持真实钢琴麦克风、蓝牙 MIDI 与空间虚拟钢琴。AI 对弹支持本地规则、本地 CoreML，以及可选的 Aria v2 网络后端。

这些是当前实现边界，不是专业能力通过结论。乐谱忠实示范、MIDI 演奏评价、表现力虚拟琴和专业虚拟指导仍以证据门为准；真机、钢琴家与研究协议未实际执行时必须保持 `pending evidence`，合法 exporter fixture 缺失时为 `blocked evidence`。

## 验证边界

- 纯模型、reducer、range、matcher、alignment、assessment 与 coaching policy 可用确定性 fixture 或 Swift harness 验证。
- SwiftUI、RealityKit、AVFoundation、CoreMIDI 与资源集成必须使用 Xcode 和 visionOS SDK。
- 手部追踪、麦克风、蓝牙 MIDI、空间对齐、Local Network 与舒适度需要 Apple Vision Pro 真机。
- 当前仓库未包含 SoundFont 和 CoreML 模型；缺少私有模型或 SeedScores 时，对应资源集成测试会跳过，不能标记为资源集成已通过。
