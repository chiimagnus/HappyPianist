# Generation Metadata

## Run info

| Item | Value |
| --- | --- |
| Source snapshot | `HappyPianist-20260713-181406.zip` |
| Commit hash | 不可用（源码归档不包含 Git 元数据） |
| Generated at | 2026-07-13T19:32:15+09:00 |
| Output language | Chinese |
| Generation mode | Canonical documentation cleanup with `neat-freak` |

## Canonical pages

- `AGENTS.md`
- `README.md`
- `docs/overview.md`
- `docs/architecture.md`
- `docs/data-flow.md`
- `docs/configuration.md`
- `docs/storage.md`
- `docs/modules/happypianist-avp.md`
- `docs/modules/happypianist-avp-practice.md`
- `docs/testing/core-function-checklist.md`

## Removed or merged pages

- `docs/dependencies.md`：必要内容并入 `docs/configuration.md`。
- `docs/glossary.md`：术语已在架构、数据流和模块页中就地解释。
- 原三份 testing checklist：合并为 `docs/testing/core-function-checklist.md`。

## Coverage gaps

- 源码归档不包含 Git 历史，因此无法记录原始仓库 HEAD。
- 当前环境未使用 Xcode 重新验证这份源码。
- 手部追踪、麦克风、Bluetooth MIDI、空间对齐与舒适度需要 Apple Vision Pro 真机。
- 源码归档不包含 `Bravura.otf`、`SalC5Light2.sf2`、Performance RNN CoreML 模型与 Aria 权重。
