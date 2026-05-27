# 🎹 LonelyPianist

An AI piano companion for Apple Vision Pro that guides you step-by-step through playing sheet music, and lets you enjoy relay improvisation with an AI partner.

[**中文**](./README.md) | English

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
![Platform](https://img.shields.io/badge/visionOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6-orange)
[![Last Update](https://img.shields.io/github/last-commit/chiimagnus/lonelypianist?label=Last%20update&style=classic)](https://github.com/chiimagnus/lonelypianist)

## What You Can Do

### 🥽 AR Guide
Import MusicXML files and get spatial practice guidance on Vision Pro (dual-staff notation + left/right hand key highlighting).

### 🎹 AI Duet (Relay Improvisation)
You play a phrase, the AI responds with its own, in an immersive space.

AI Duet currently uses on-device CoreML / local rule backends; no desktop Python service is required.

## Releases

- The repo is primarily source-code based: **requires local Xcode build** — no pre-built notarized app is provided.

- The soundfont `SalC5Light2.sf2` for `LonelyPianistAVP` is large and not included in the repo by default. You can download it from [GitHub Releases](https://github.com/chiimagnus/LonelyPianist/releases/tag/v0.1.6-beta2) and place it at:
  - `LonelyPianistAVP/Resources/Audio/SoundFonts/SalC5Light2.sf2`

## Acknowledgements

- [Anticipation](https://github.com/jthickstun/anticipation) · [Anticipatory Music Transformer](https://arxiv.org/abs/2306.08620)
- [stanford-crfm/music-large-800k](https://huggingface.co/stanford-crfm/music-large-800k)
- Apple CoreMIDI / RealityKit / ARKit
- Salamander Grand Piano soundfont samples
- Special thanks to 南客松S2, `njuer勇闯互联网`, `罗恩`, and `大宝哥` — together our team won the Gold Award at this hackathon 🏆

## License

This project is licensed under [AGPL-3.0](./LICENSE.APGLv3).
