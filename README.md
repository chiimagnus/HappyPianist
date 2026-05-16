# 🎹 LonelyPianist

一款 XR空间设备上的 AI 钢琴伙伴，戴上眼镜，它会引导你一步步弹奏；并且你可以享受与 ta 的接力即兴演奏。

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20visionOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6-orange)

## 你可以用它做什么

| 🥽 AR Guide | 导入 MusicXML，在 Vision Pro 上做空间练习引导（双谱表五线谱 + 左右手键位高亮） | visionOS |

## 发布物（当前现状）

- 当前仓库主要以“源码运行”为主：**需要 Xcode 本地构建**，暂未提供可直接下载运行的 notarized app。
- GitHub Releases 里可能会放置**资源文件**（例如音色文件、示例谱面），用于补齐体积较大的素材（见路线 C）。

## 我想“先跑起来”该选哪条路

### 路线 C：在 Apple Vision Pro 上练习（visionOS）

你需要：
- Xcode 26+
- visionOS Simulator（可用）或 Vision Pro 真机（推荐）

步骤：
1. 打开工程后，在本地 Xcode 中选择或创建 `LonelyPianistAVP` scheme 并运行
2. 在 2D Window 选择钢琴类型（真实 / 虚拟 / 蓝牙 MIDI）
3. 完成准备阶段（校准或放置）后进入曲库并导入 MusicXML，然后开始练习

可选资源（推荐）：
- `LonelyPianistAVP` 的音色文件 `SalC5Light2.sf2` 体积较大，仓库默认不内置；可以从 GitHub Releases 的“资源文件”里下载并放到：
  - `LonelyPianistAVP/Resources/Audio/SoundFonts/SalC5Light2.sf2`

## Acknowledgements

- [Anticipation](https://github.com/jthickstun/anticipation) · [Anticipatory Music Transformer](https://arxiv.org/abs/2306.08620)
- [stanford-crfm/music-large-800k](https://huggingface.co/stanford-crfm/music-large-800k)
- Apple CoreMIDI / RealityKit / ARKit
- Salamander Grand Piano 音色采样
- 感谢南客松S2，感谢`njuer勇闯互联网`、`罗恩`、`大宝哥`，让这个项目、我们这个团队荣获此次黑客松的金奖～

## License

本项目基于 [AGPL-3.0](./LICENSE) 开源。
