# Generation Metadata

## Run info

| Item | Value |
| --- | --- |
| Commit hash | d79c229a |
| Branch name | crh3 |
| Generated at | 2026-06-01T12:26:42+08:00 |
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

## Current Coverage Gaps

- 本仓库没有 `.github/workflows/`，自动化验证以本地命令为准。
- AVP 的手部追踪、平面检测、BLE MIDI、Microphone 与空间舒适度需要真机验证。
- `LonelyPianistAVP/Resources/Audio/SoundFonts/SalC5Light2.sf2` 仓库默认不内置。
- AVP 的 Local Network（Bonjour 发现 + HTTP/WS 连接）需要真机与局域网环境配合（用于可选网络后端 Aria v2）。
