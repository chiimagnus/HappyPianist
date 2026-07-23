# 🎹 HappyPianist

An AI piano companion for Apple Vision Pro that guides you step-by-step through playing sheet music, and lets you enjoy relay improvisation with an AI partner.

[**中文**](./README.md) | English

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
![Platform](https://img.shields.io/badge/visionOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6-orange)
[![Last Update](https://img.shields.io/github/last-commit/chiimagnus/happypianist?label=Last%20update&style=classic)](https://github.com/chiimagnus/happypianist)

![scene1](docs/assets/scene1.jpg)

## What You Can Do

### 🥽 AR Guide
Import MusicXML files and get spatial practice guidance on Vision Pro (dual-staff notation projection and key highlighting; hand information remains unknown when the source cannot support it).

### 🎹 AI Duet (Relay Improvisation)
You play a phrase, the AI responds with its own, in an immersive space.

AI Duet uses the backend selected by the user: on-device CoreML, local rule, or an optional network backend. A failed request stops rather than silently falling back to another backend.

Optional: you can also run `python_backend/aria_server/` on a Mac and let AVP connect to an Aria v2 network backend via Bonjour + HTTP/WS (useful for on-device testing and low-latency streaming).

## Capability and Evidence Boundary

Score-driven playback, MIDI objective metrics, calibrated virtual-piano velocity, and scoped practice actions are implemented practice features. They are not claims of pianist-grade reference performance, professional scoring, a validated expressive instrument, or a replacement for a piano teacher.

Those professional claims remain `pending evidence` until licensed multi-exporter corpus coverage, device measurements, blinded pianist review, expert-label agreement, and coaching-efficacy studies are completed. Missing lawful exporter fixtures are `blocked evidence`. See the [quality boundary](docs/piano-performance-quality.md) and the [claim gates](docs/testing/piano-capability-claim-gates.md).

## Releases

- The repo is primarily source-code based: **requires local Xcode build** — no pre-built notarized app is provided.

- The soundfont `SalC5Light2.sf2` for `HappyPianistAVP` is large and not included in the repo by default. You can download it from [GitHub Releases](https://github.com/chiimagnus/HappyPianist/releases/tag/v0.1.6-beta2) and place it at:
  - `HappyPianistAVP/Resources/Audio/SoundFonts/SalC5Light2.sf2`

- Seed scores and the CoreML model are also private resources. Tests skipped because those resources are absent are not evidence that their integrations passed.

## Acknowledgements

- [Anticipation](https://github.com/jthickstun/anticipation) · [Anticipatory Music Transformer](https://arxiv.org/abs/2306.08620)
- [stanford-crfm/music-large-800k](https://huggingface.co/stanford-crfm/music-large-800k)
- Apple CoreMIDI / RealityKit / ARKit
- Salamander Grand Piano soundfont samples
- Special thanks to 南客松S2, `njuer勇闯互联网`, `罗恩`, and `大宝哥` — together our team won the Gold Award at this hackathon 🏆

## License

This project is licensed under [AGPL-3.0](./LICENSE.APGLv3).
