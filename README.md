# 🎹 LonelyPianist

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_14%2B-blue?style=for-the-badge&logo=apple&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange?style=for-the-badge&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="License">
</p>

---

## 一句话介绍

LonelyPianist 是一个“练琴辅助”工具集合：

- `LonelyPianist/`：macOS 主应用（MIDI 监听与映射、对话模式入口等）
- `LonelyPianistAVP/`：visionOS（Apple Vision Pro）端 AR Guide 原型（手部追踪 + 校准 + 指引）
- `piano_dialogue_server/`：本机 Python 工作区（Piano Dialogue 后端 + OMR：PDF/图片→MusicXML）

## 📌 文档入口（完全拆分）

- macOS 主应用：`LonelyPianist/README.md`
- Apple Vision Pro（AR Guide）：`LonelyPianistAVP/README.md`
- 本机 Python（Dialogue + OMR）：`piano_dialogue_server/README.md`

（内部）研发计划/审计：

- 最新需求草案：`.github/features/1.md`
- 过程文档：`.github/features/`

## 📁 仓库结构

- `LonelyPianist.xcodeproj`：Xcode 工程入口
- `LonelyPianist/`：macOS App 源码
- `LonelyPianistAVP/`：visionOS App 源码
- `LonelyPianistTests/`：macOS 单测（Swift Testing）
- `LonelyPianistAVPTests/`：visionOS 单测（Swift Testing）
- `piano_dialogue_server/`：Python 服务与 OMR 工具链

## 🚀 快速开始（只保留最短入口）

1. 打开 Xcode 工程：`LonelyPianist.xcodeproj`
2. 选择 Scheme：
   - macOS：`LonelyPianist`
   - visionOS：`LonelyPianistAVP`
3. 详细“运行/验收/排障”请按各目录 `README.md` 执行（避免重复与漂移）。

## 🙏 致谢

本项目的部分能力依赖以下开源项目/标准：

- `oemer`：用于 OMR（乐谱 PDF/图片 → MusicXML）的核心推理组件（Python）。
- `PyMuPDF`：用于 PDF 渲染与页面提取（Python）。
- `FastAPI` / `Uvicorn`：用于本机 Python 服务与 HTTP 接口。
- MusicXML：乐谱交换格式标准（AVP 导入以 MusicXML 为主）。

---

<p align="center">
  Made with 🎹 by <a href="https://github.com/chiimagnus">chiimagnus</a>
</p>
