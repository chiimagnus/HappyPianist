# 🎹 LonelyPianist

- `LonelyPianist/`：macOS 端（MIDI 监听与映射、对话模式入口等）
- `LonelyPianistAVP/`：visionOS 端 AR Guide 原型（手部追踪 + 校准 + 指引）
- `piano_dialogue_server/`： Python（Piano Dialogue 后端 + OMR：PDF/图片→MusicXML）

## 📁 仓库结构

- `LonelyPianist.xcodeproj`：Xcode 工程入口
- `LonelyPianist/`：macOS App 源码
- `LonelyPianistAVP/`：visionOS App 源码
- `LonelyPianistTests/`：macOS 单测（Swift Testing）
- `LonelyPianistAVPTests/`：visionOS 单测（Swift Testing）
- `piano_dialogue_server/`：Python 服务与 OMR 工具链

## 🚀 快速开始

1. 打开 Xcode 工程：`LonelyPianist.xcodeproj`
2. 选择 Scheme：
   - macOS：`LonelyPianist`
   - visionOS：`LonelyPianistAVP`
3. 详细“运行/验收/排障”请按各目录 `README.md` 执行。

---

<p align="center">
  Made with 🎹 by <a href="https://github.com/chiimagnus">chiimagnus</a>
</p>
