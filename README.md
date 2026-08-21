# HappyPianist

[English](./README.en.md) | 中文

HappyPianist 是面向 Apple Vision Pro 的空间钢琴练习应用：将 MusicXML 转为练习、记谱和空间引导，支持麦克风、蓝牙 MIDI 与虚拟钢琴输入。

![scene](docs/assets/scene1.jpg)

## 快速开始

```bash
make doctor
make build
make test
make build:mac
make test:mac
```

共享核心可单独验证：`swift test --package-path Packages/HappyPianistCore`。架构、数据契约和验证入口见[项目概览](docs/overview.md)。

## 致谢

- [Anticipation](https://github.com/jthickstun/anticipation) 与 [Anticipatory Music Transformer](https://arxiv.org/abs/2306.08620)
- [stanford-crfm/music-large-800k](https://huggingface.co/stanford-crfm/music-large-800k)
- Salamander Grand Piano 音色采样
- 感谢南客松 S2、`njuer勇闯互联网`、`罗恩`、`大宝哥` 对项目的支持

## 许可证

本项目基于 [AGPL-3.0](LICENSE.APGLv3) 开源。
