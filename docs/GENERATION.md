# Generation Metadata

## Run info

| Item | Value |
| --- | --- |
| Commit hash | 98198f8 |
| Branch name | crh1 |
| Generated at | 2026-05-22T21:52:09+08:00 |
| Output language | Chinese |
| Generation mode | Full docs reconciliation via `neat-freak` against current working tree |

## Pages

- `AGENTS.md`
- `README.md`
- `docs/overview.md`
- `docs/architecture.md`
- `docs/data-flow.md`
- `docs/configuration.md`
- `docs/dependencies.md`
- `docs/storage.md`
- `docs/glossary.md`
- `docs/modules/lonelypianist-macos.md`
- `docs/modules/lonelypianist-avp.md`
- `docs/modules/lonelypianist-avp-practice.md`
- `docs/modules/improv-engines.md`
- `docs/modules/piano-dialogue-server.md`
- `docs/dev/piano-highlight-regression-checklist.md`

## Current Coverage Gaps

- 本仓库没有 `.github/workflows/`，自动化验证以本地命令为准。
- AVP 的手部追踪、平面检测、BLE MIDI、Bonjour/Local Network、Microphone 与空间舒适度需要真机验证。
- `LonelyPianistAVP/Resources/Audio/SoundFonts/SalC5Light2.sf2` 仓库默认不内置。
- Python 依赖没有 lockfile，模型权重与下载镜像依赖本地环境。
