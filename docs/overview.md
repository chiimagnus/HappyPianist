# 项目概览

HappyPianist 是一个面向 Apple Vision Pro 的钢琴练习应用。仓库包含 visionOS App、测试、RealityKit 内容包，以及可选的 Mac 侧 Aria v2 Python 服务。

## 运行单元

| 运行单元 | 入口 | 作用 |
| --- | --- | --- |
| visionOS App | `HappyPianistAVP/` | 准备、曲库、练习、录制、AI 对弹与沉浸空间。 |
| visionOS Tests | `HappyPianistAVPTests/` | MusicXML、练习、输入、回放、反馈、窗口与服务测试。 |
| RealityKit 内容包 | `Packages/RealityKitContent/` | Reality Composer Pro 资产与 bundle。 |
| Aria v2 服务（可选） | `python_backend/aria_server/` | Bonjour + HTTP/WS 网络即兴后端。 |

Xcode 工程只有 `HappyPianistAVP` 与 `HappyPianistAVPTests` 两个 target；仓库中不存在 macOS App target。

## 按问题导航

| 想了解什么 | 文档 |
| --- | --- |
| 模块、依赖方向、运行时边界和危险修改区 | [architecture.md](architecture.md) |
| MusicXML、输入、练习、反馈、录制与 AI 的数据流 | [data-flow.md](data-flow.md) |
| 曲谱真值、参考演奏、输入证据、演奏评价、虚拟指导与专业验收路线 | [piano-performance-quality.md](piano-performance-quality.md) |
| Xcode、权限、依赖、资源、设置与可选服务 | [configuration.md](configuration.md) |
| Documents 目录、JSON、曲库、进度与诊断文件 | [storage.md](storage.md) |
| App 窗口、钢琴模式、曲库与沉浸空间 | [modules/happypianist-avp.md](modules/happypianist-avp.md) |
| 练习 session、判定、进度、反馈与回放 | [modules/happypianist-avp-practice.md](modules/happypianist-avp-practice.md) |
| 日常需要验证的核心功能 | [testing/core-function-checklist.md](testing/core-function-checklist.md) |
| 钢琴演奏专业化的快照、真机、盲听与教学证据 | [testing/piano-performance-validation.md](testing/piano-performance-validation.md) |

## 产品主流程

```text
进入曲库并导入 MusicXML
-> 从左上角“选择钢琴”打开 pushed 准备窗口
-> 完成校准或虚拟琴放置并返回曲库
-> 选择曲目、查看右侧只读事实并点击主内容中的唯一“开始练习”按钮
-> 练习窗口准备曲谱并恢复精确版本的进度
-> 演奏、判定并保存小节事实
-> 查看即时反馈、总结和恢复地图
```

练习输入支持真实钢琴麦克风、蓝牙 MIDI 与空间虚拟钢琴。AI 对弹支持本地规则、本地 CoreML，以及可选的 Aria v2 网络后端。

## 验证边界

- 纯模型、reducer、range、matcher 等逻辑可在跨平台 Swift harness 中验证。
- SwiftUI、RealityKit、AVFoundation、CoreMIDI 与资源集成必须使用 Xcode 和 visionOS SDK。
- 手部追踪、麦克风、蓝牙 MIDI、空间对齐、Local Network 与舒适度需要 Apple Vision Pro 真机。
- 当前源码归档缺少 Bravura、SoundFont 和 CoreML 模型；相关测试不能标记为已通过。
