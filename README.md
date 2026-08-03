# HappyPianist

[English](./README.en.md) | 中文

HappyPianist 是一个钢琴练习应用：visionOS App 将 MusicXML 转成空间练习引导；macOS App 专注于沙盒内的 2D MusicXML 导入与系统可见 MIDI 练习。Mac 导入只在 `fileImporter` 的临时 security scope 内复制曲谱，不保存外部 URL 或 bookmark。

![scene](docs/assets/scene1.jpg)

## 致谢

- [Anticipation](https://github.com/jthickstun/anticipation) 与 [Anticipatory Music Transformer](https://arxiv.org/abs/2306.08620)
- [stanford-crfm/music-large-800k](https://huggingface.co/stanford-crfm/music-large-800k)
- Salamander Grand Piano 音色采样
- 感谢南客松 S2、`njuer勇闯互联网`、`罗恩`、`大宝哥` 对项目的支持

## 许可证

本项目基于 [AGPL-3.0](LICENSE.APGLv3) 开源。
