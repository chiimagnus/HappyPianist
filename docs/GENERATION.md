# 文档同步元数据

| 项目 | 值 |
| --- | --- |
| 源提交 | `3ba1f4e` |
| 生成日期 | 2026-09-30 |
| 方法 | `neat-freak`：CodeGraph 核对源码边界，合并重复说明并检查链接、路径和命令。 |

## Canonical 页面

- `AGENTS.md`、`HappyPianistAVP/AGENTS.md`
- `README.md`、`README.en.md`
- `docs/overview.md`、`architecture.md`、`data-flow.md`、`configuration.md`、`storage.md`、`piano-performance-quality.md`、`testing.md`、`ai-companion-requirements.md`
- `python_backend/README.md`

`.github/features/` 与 `.github/archived_features/` 是执行计划和审计证据，不承担长期架构说明；`python_backend/aria/README.md` 是上游 Aria 文档，保留原文。依赖生成目录和 Python 虚拟环境中的第三方 README 不属于仓库文档。已删除仅复述源码包结构的 `docs/modules/` 页面。

## 覆盖缺口

- 2026-09-30 在全新 visionOS 27.0 Apple Vision Pro Simulator 上 `make build:simulator` 通过；完整 `HappyPianistAVPTests` 为 1033 tests / 1022 passed / 11 failed / 0 skipped，失败仍集中在 hand rig / hand motion / local sampler / demonstration hands，Qwen/Companion 无新增失败。Qwen 已切到本地 NF4 4-bit，定向 Python 回归与固定 60-case Qwen → Aria 服务级 E2E 双跑通过；Stage A 仍有 `settled_end` 语义质量缺口；Aria true-streaming P3 probe 因安全 commit window 过晚而 No-Go，继续保留 HTTP full-response。详见[测试](testing.md)。
- 真机硬件、钢琴家盲评、教师标注和 coaching 研究仍为 `pending evidence`；合法多 exporter fixture 仍为 `blocked evidence`。
