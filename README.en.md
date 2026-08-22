# HappyPianist

[中文](./README.md) | English

HappyPianist is a piano practice app for Apple Vision Pro. It converts MusicXML into spatial practice guidance and supports three input methods: audio, Bluetooth MIDI, and a virtual piano.

![scene](docs/assets/scene1.jpg)

## Quick start

```bash
make doctor
make build:mac
make test:mac
make build:simulator
make test:simulator
```

The shared core can be tested with `swift test --package-path Packages/HappyPianistCore`. See the [project overview](docs/overview.md) for architecture, data contracts, and validation.

## Acknowledgements

- [Anticipation](https://github.com/jthickstun/anticipation) and [Anticipatory Music Transformer](https://arxiv.org/abs/2306.08620)
- [stanford-crfm/music-large-800k](https://huggingface.co/stanford-crfm/music-large-800k)
- Salamander Grand Piano soundfont samples
- Special thanks to 南客松 S2, `njuer勇闯互联网`, `罗恩`, and `大宝哥` for supporting the project

## License

This project is licensed under [AGPL-3.0](LICENSE.APGLv3).
