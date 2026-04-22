# Deepwiki Generation Metadata

## Generation Summary
| 字段 | 值 |
| --- | --- |
| Commit hash | `a9b6a0e` |
| Branch | `crh` |
| Generation timestamp (local) | `2026-04-22 16:27:31 +0800` |
| Output language | `Chinese (中文)` |
| Mode | `增量更新（update）` |

## Generated / Updated Page List
- `INDEX.md`
- `GENERATION.md`
- `business-context.md`
- `overview.md`
- `architecture.md`
- `data-flow.md`
- `configuration.md`
- `storage.md`
- `testing.md`
- `workflow.md`
- `troubleshooting.md`
- `glossary.md`
- `modules/lonelypianist-avp.md`

## Copied Asset List
- `assets/.gitkeep`（用于固定保留 `assets/` 目录）

## Notes
- 本次增量更新重点是对齐 `crh` 分支下的 AVP 三步流程（Step 1 校准、Step 2 选曲/试听、Step 3 练习）与 Song Library 子系统事实。
- 同步了曲库 bundled seed 音频、试听状态与相关测试样本，并保留 legacy `ImportedScores` 清理说明。
- 已修正多处历史路径漂移（例如 AVP 视图路径迁移到 `Views/` 子目录）。
- 已保留并显式更新 Coverage Gaps（CI 缺失、AVP 共享 scheme 不可见）。
