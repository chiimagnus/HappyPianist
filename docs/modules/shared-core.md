# 共享核心模块

`Packages/HappyPianistCore` 是跨 App 的唯一低层 Swift Package。每个 product 只暴露其 consumer 需要的稳定契约；App target 不保留同名实现或兼容副本。

## 当前依赖图

```text
Diagnostics → ∅
HappyPianistAVP → Diagnostics
```

## Diagnostics

`Diagnostics` 拥有 `DiagnosticEvent` 及其安全引用、结构化 reporting、OSLog sink、七日 JSONL store 和用户主动导出的 ZIP archive。它不知晓 Practice、MusicXML、Library、MIDI、SwiftUI、RealityKit、ARKit 或 AVFoundation。

环境信息通过 `DiagnosticsEnvironmentProviding` 注入；默认 provider 只读取当前 host bundle 的版本与系统版本。ZIPFoundation 由这个本地 package 单次声明并被 archive implementation 使用，App target 不直接链接它。

输出指标、音频恢复、记谱 fallback 和 coaching diagnostics 仍在各自 App owner 中；它们只向 `Diagnostics` 生成低基数、可过滤的 `DiagnosticEvent`。可导出记录不得包含绝对路径、原始谱面、逐音输入、AI 正文、凭据或设备显示名。
