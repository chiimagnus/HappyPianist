# 🎹 LonelyPianist

一款 XR空间设备上的 AI 钢琴伙伴，戴上眼镜，它会引导你一步步弹奏；并且你可以享受与 ta 的接力即兴演奏。

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20visionOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6-orange)

## 这是什么

LonelyPianist 把钢琴输入拆成三条清晰的体验线：

| 体验 | 你得到什么 | 运行面 |
| --- | --- | --- |
| 🎛 MIDI → 控制台 | 把单音 / 和弦映射成文本、快捷键和系统动作 | macOS |
| 🎭 Piano Dialogue | 弹一句、停一下、AI 回一句，并落成 take | macOS + 本地 Python |
| 🥽 AR Guide | 导入 MusicXML，在 Vision Pro 上做空间练习引导 | visionOS |

## 为什么值得试

- **本地优先**：核心体验尽量在你的机器上完成，不依赖云端对话服务。
- **三端连贯**：macOS 负责输入、录音和对话，visionOS 负责练习引导，Python 负责生成。
- **可验证**：每个主要功能都有对应的 Swift Testing / Python 冒烟入口。

## 快速开始

### 1. 启动 Python Dialogue 服务

```bash
cd piano_dialogue_server
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

export AMT_MODEL_DIR=/path/to/music-large-800k
export AMT_DEVICE=mps   # 或 cuda / cpu

python -m uvicorn server.main:app --host 127.0.0.1 --port 8765
```

健康检查：

```bash
curl -s http://127.0.0.1:8765/health
```

### 2. 打开 macOS App

```bash
open LonelyPianist.xcodeproj
```

在 Xcode 里选择 `LonelyPianist` scheme 并运行。首次使用前，请在**系统设置 → 隐私与安全性 → 辅助功能**中授权，否则按键注入不会生效。

### 3. 体验 Vision Pro 练习

```bash
# 打开工程后，在本地 Xcode 里选择 / 创建 LonelyPianistAVP scheme
```

## 项目结构

```text
LonelyPianist.xcodeproj/      # Xcode 工程
LonelyPianist/                # macOS App
LonelyPianistAVP/             # visionOS 原型
piano_dialogue_server/        # 本地 Python 服务
```

## 文档入口

- 想先理解产品：[`business-context.md`](.github/deepwiki/business-context.md)
- 想先看工程：[`overview.md`](.github/deepwiki/overview.md)
- 想看模块分解：[`INDEX.md`](.github/deepwiki/INDEX.md)
- 想看 macOS 用法：[`LonelyPianist/README.md`](LonelyPianist/README.md)
- 想看 visionOS 用法：[`LonelyPianistAVP/README.md`](LonelyPianistAVP/README.md)
- 想看 Python 服务：[`piano_dialogue_server/README.md`](piano_dialogue_server/README.md)

## 当前技术栈

| 层 | 技术 |
| --- | --- |
| macOS UI | SwiftUI · `@Observable` · CoreMIDI · SwiftData |
| visionOS | RealityKit · ARKit HandTracking · MusicXML |
| 服务端 | FastAPI · WebSocket · Uvicorn |
| 推理 | PyTorch · Transformers · Anticipation |
| 测试 | Swift Testing + Python 脚本 |

## Acknowledgements

- [Anticipation](https://github.com/jthickstun/anticipation) · [Anticipatory Music Transformer](https://arxiv.org/abs/2306.08620)
- [stanford-crfm/music-large-800k](https://huggingface.co/stanford-crfm/music-large-800k)
- Apple CoreMIDI / RealityKit / ARKit
- Salamander Grand Piano 音色采样

## License

本项目基于 [AGPL-3.0](./LICENSE) 开源。
