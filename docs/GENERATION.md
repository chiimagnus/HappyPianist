# 文档同步元数据

| 项目 | 值 |
| --- | --- |
| 源提交 | `f555dfa557c9d07b65ad4739c7549805459fd748` |
| 生成日期 | 2026-08-23 |
| 方法 | `neat-freak`：CodeGraph 核对源码边界，合并重复说明并检查链接、路径和命令。 |

## Canonical 页面

- `AGENTS.md`、`HappyPianistAVP/AGENTS.md`
- `README.md`、`README.en.md`
- `docs/overview.md`、`architecture.md`、`data-flow.md`、`configuration.md`、`storage.md`、`piano-performance-quality.md`、`testing.md`
- `python_backend/README.md`

`.github/features/` 与 `.github/archived_features/` 是执行计划和审计证据，不承担长期架构说明；`python_backend/aria/README.md` 是上游 Aria 文档，保留原文。依赖生成目录和 Python 虚拟环境中的第三方 README 不属于仓库文档。已删除仅复述源码包结构的 `docs/modules/` 页面。

## 覆盖缺口

- 本次为文档整理，只验证文档链接、路径和命令；未因文档改动重跑 build/test。
- 真机硬件、钢琴家盲评、教师标注和 coaching 研究仍为 `pending evidence`；合法多 exporter fixture 仍为 `blocked evidence`，详见[测试](testing.md)。
