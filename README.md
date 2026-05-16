# 🎹 LonelyPianist

一款 Apple Vision Pro 上的 AI 钢琴伙伴，它会引导你一步步弹奏；并且你可以享受与 ta 的接力即兴演奏。

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
![Platform](https://img.shields.io/badge/visionOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6-orange)

## 你可以用它做什么

### 🥽 AR Guide 
导入 MusicXML，在 Vision Pro 上做空间练习引导（双谱表五线谱 + 左右手键位高亮）

### 🤝 AI 对弹（接力即兴）
你弹一句、AI 回一句；在沉浸空间中回放（支持自动发现本地后端）

可选：开启 AI 对弹（本地后端）
1. 按 `piano_dialogue_server/README.md` 启动本地服务（建议 `--host 0.0.0.0 --port 8765`，便于同网段设备访问）
2. 确保运行 AVP 的设备与后端在**同一局域网**
3. 在 AVP 端允许 **Local Network** 权限（否则 Bonjour 自动发现会显示为 denied）

## 发布物

- 当前仓库主要以“源码运行”为主：**需要 Xcode 本地构建**，暂未提供可直接下载运行的 notarized app。
- GitHub Releases 里可能会放置**资源文件**（例如音色文件、示例谱面），用于补齐体积较大的素材（见路线 C）。

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
