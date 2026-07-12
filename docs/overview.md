# 项目概览

HappyPianist 当前是一个 visionOS 26.0 钢琴练习应用。仓库包含 AVP App、测试、RealityKit 内容包，以及可选的 Mac 侧 Aria v2 Python 服务。

## 运行单元

| 运行单元 | 入口 | 作用 |
| --- | --- | --- |
| visionOS App | `HappyPianistAVP/` | 准备、曲库、练习、录制、AI 对弹与沉浸空间。 |
| visionOS Tests | `HappyPianistAVPTests/` | MusicXML、练习、输入、回放、反馈、窗口与 AI 服务测试。 |
| RealityKit 内容包 | `Packages/RealityKitContent/` | Reality Composer Pro 资产与 bundle。 |
| Aria v2 服务（可选） | `python_backend/aria_server/` | Bonjour + HTTP/WS 网络即兴后端。 |

Xcode 工程只有 `HappyPianistAVP` 与 `HappyPianistAVPTests` 两个 target。仓库中不存在 macOS App target。

## 按问题导航

| 想了解什么 | 文档 |
| --- | --- |
| 整体模块、依赖方向和危险修改区 | [architecture.md](architecture.md) |
| 数据如何从 MusicXML、输入源流到练习与反馈 | [data-flow.md](data-flow.md) |
| App 窗口、钢琴模式、曲库与沉浸空间 | [modules/happypianist-avp.md](modules/happypianist-avp.md) |
| 练习 session、判定、进度、反馈和回放 | [modules/happypianist-avp-practice.md](modules/happypianist-avp-practice.md) |
| Xcode、权限、UserDefaults、资源与 Python 服务 | [configuration.md](configuration.md) |
| JSON 文件和 Documents 目录结构 | [storage.md](storage.md) |
| Apple framework、SwiftPM 与外部资源 | [dependencies.md](dependencies.md) |
| 术语 | [glossary.md](glossary.md) |
| 可恢复练习验收 | [testing/practice-learning-loop-p1-checklist.md](testing/practice-learning-loop-p1-checklist.md) |
| 正反馈与空间效果验收 | [testing/practice-feedback-usability-checklist.md](testing/practice-feedback-usability-checklist.md) |
| 曲库右侧练习 Ornament 与诊断导出验收 | [testing/library-practice-ornament-checklist.md](testing/library-practice-ornament-checklist.md) |

## 产品主流程

```text
选择钢琴模式
-> 完成校准或虚拟琴放置
-> 进入曲库并导入 MusicXML
-> 在曲库右侧 Ornament 查看进度并设置本轮配置
-> 演奏、判定、保存小节事实
-> 查看即时反馈、总结和恢复地图
```

练习输入支持：

- 真实钢琴麦克风识别
- 蓝牙 MIDI
- 空间虚拟钢琴

AI 对弹支持：

- 本地规则后端
- 本地 CoreML 后端（需要模型资源）
- Aria v2 HTTP/WS 网络后端（需要 Mac 服务与 Local Network 权限）

## 验证边界

- 纯模型、reducer、range、matcher 等逻辑可以在跨平台 Swift harness 中验证。
- App target、SwiftUI、RealityKit、AVFoundation、CoreMIDI 与资源集成必须使用 Xcode 和 visionOS SDK。
- 手部追踪、麦克风、蓝牙 MIDI、真实空间对齐、Local Network 与舒适度需要 Apple Vision Pro 真机。
- 当前源码归档缺少 Bravura、SoundFont 和 CoreML 模型；相关测试不能标记为已通过。
