# 共享核心模块

`Packages/HappyPianistCore` 是跨 App 的唯一低层 Swift Package。每个 product 只暴露其 consumer 需要的稳定契约；App target 不保留同名实现或兼容副本。

## 当前依赖图

```text
Diagnostics → ∅
MusicXML → ∅
MIDI → Diagnostics
Practice → Diagnostics, MusicXML
HappyPianistAVP → Diagnostics, MusicXML, MIDI, Practice
HappyPianistAVPTests → Diagnostics, MusicXML, MIDI, Practice, HappyPianistTestFixtures
```

## Diagnostics

`Diagnostics` 拥有 `DiagnosticEvent` 及其安全引用、结构化 reporting、OSLog sink、七日 JSONL store 和用户主动导出的 ZIP archive。它不知晓 Practice、MusicXML、Library、MIDI、SwiftUI、RealityKit、ARKit 或 AVFoundation。

环境信息通过 `DiagnosticsEnvironmentProviding` 注入；默认 provider 只读取当前 host bundle 的版本与系统版本。ZIPFoundation 由这个本地 package 单次声明并被 archive implementation 使用，App target 不直接链接它。

音频恢复、记谱 fallback 和 coaching diagnostics 仍在各自 App owner 中；`MIDI` 的输出指标和其余 owner 都只向 `Diagnostics` 生成低基数、可过滤的 `DiagnosticEvent`。可导出记录不得包含绝对路径、原始谱面、逐音输入、AI 正文、凭据或设备显示名。

## MusicXML、Practice 与测试 fixture

`MusicXML` 拥有 MusicXML/MXL 模型、解析、结构扩展与谱面语义计算；它不依赖 Practice、Library、MIDI 或 Diagnostics。

`Practice` 依赖 `MusicXML` 与 `Diagnostics`，拥有 `PracticePreparationService`、`ScorePerformancePlanBuilder`、`ScorePerformancePlan`、`PracticeStepBuilder`、琴键高亮与记谱投影。它的公开值契约可跨 actor 安全传递；它不保留 App/Notation 的类型，也不引入「有 steps、无小节」的兼容结果。App 的 session runtime、playback、曲库与视图保留在 App，单向消费 preparation 结果。

用户文件先经过单一 `MusicXMLImportSafetyPolicy`：只接受有限大小的常规文件；MXL 在读取 central directory 和每次 extraction 前检查 entry 数量、声明解压大小、总大小、压缩比与安全的相对 archive name。拒绝结果是无路径的 typed reason，不返回部分 score。

`HappyPianistTestFixtures` 只提供测试 bundle 内的 fixture URL；App production target 不链接它，原 `HappyPianistAVPTests/Fixtures` 路径不存在。

## MIDI

`MIDI` 拥有 MIDI 1/2 输入事件、稳定 endpoint ID、host-time 转换、CoreMIDI 输入/输出 transport、端点路由通知和输出指标。它只依赖 `Diagnostics`，不依赖 Practice、录制、AI、SwiftUI 或 RealityKit。

visionOS composition root 显式选择 `.allCurrentSources`，以保留当前所有来源订阅行为；以后平台选择单个端点时只保存 `endpointUniqueID`。旧的 Bluetooth 命名和可变 `sourceIndex` 身份均不存在。输入在 route 变化后重新连接，并通过 availability callback 报告所选端点不可用；播放取消与 look-ahead 发送由同一 mutex generation gate 原子化。
