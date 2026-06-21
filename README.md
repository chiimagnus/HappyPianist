# 🎹 LonelyPianist

一款 Apple Vision Pro 上的 AI 钢琴伙伴，它会引导你一步步弹奏；并且你可以享受与 ta 的接力即兴演奏。

中文 | [**English**](./README.en.md)

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
![Platform](https://img.shields.io/badge/visionOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6-orange)
[![Last Update](https://img.shields.io/github/last-commit/chiimagnus/lonelypianist?label=Last%20update&style=classic)](https://github.com/chiimagnus/lonelypianist)

![scene1](docs/assets/scene1.jpg)

## 你可以用它做什么

### 🥽 AR Guide 
导入 MusicXML，在 Vision Pro 上做空间练习引导（双谱表五线谱 + 左右手键位高亮）

### 🎹 AI 对弹（接力即兴）
你弹一句、AI 回一句；在沉浸空间中回放。

AI 对弹默认使用 AVP 端的本地 CoreML / 本地规则后端，不需要电脑端 Python 服务。

可选：你也可以在 Mac 上启动 `python_backend/aria_server/`，让 AVP 通过 Bonjour + HTTP/WS 连接 Aria v2 网络后端（适合真机联调与低延迟 streaming 验证）。

## 发布物

- 当前仓库主要以“源码运行”为主：**需要 Xcode 本地构建**，暂未提供可直接下载运行的 notarized app。

- `LonelyPianistAVP` 的音色文件 `SalC5Light2.sf2` 体积较大，仓库默认不内置；可以从 [GitHub Releases 的“资源文件”](https://github.com/chiimagnus/LonelyPianist/releases/tag/v0.1.6-beta2)里下载并放到：
  - `LonelyPianistAVP/Resources/Audio/SoundFonts/SalC5Light2.sf2`

## Acknowledgements

- [Anticipation](https://github.com/jthickstun/anticipation) · [Anticipatory Music Transformer](https://arxiv.org/abs/2306.08620)
- [stanford-crfm/music-large-800k](https://huggingface.co/stanford-crfm/music-large-800k)
- Apple CoreMIDI / RealityKit / ARKit
- Salamander Grand Piano 音色采样
- 感谢南客松S2，感谢`njuer勇闯互联网`、`罗恩`、`大宝哥`，让这个项目、我们这个团队荣获此次黑客松的金奖～

## License

本项目基于 [AGPL-3.0](./LICENSE.APGLv3) 开源。
