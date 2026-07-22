# 文档同步元数据

## 本次运行

| 项目 | 值 |
| --- | --- |
| 仓库来源 | 用户提供的源码归档快照 |
| 源归档 | `HappyPianist-20260722-180030.zip` |
| 源提交 | 不可用（原归档未包含 `.git`） |
| 本地同步基线 | `dcb1c4753e63662656997ef48f5e9d1d103c99f7` |
| 生成时间 | 2026-07-22T10:12:23Z |
| 输出语言 | 中文 |
| 同步方式 | 使用 `neat-freak` 对齐并统一项目文档语言 |

## 权威文档

- `AGENTS.md`
- `README.md`
- `docs/overview.md`
- `docs/architecture.md`
- `docs/data-flow.md`
- `docs/piano-performance-quality.md`
- `docs/configuration.md`
- `docs/storage.md`
- `docs/modules/happypianist-avp.md`
- `docs/modules/happypianist-avp-practice.md`
- `docs/testing/core-function-checklist.md`
- `docs/testing/piano-performance-validation.md`

## 同步摘要

- 统一用户入口、架构、模块、存储与验证文档中的中文标题和叙述。
- 将旧英文入口 `README.en.md` 收敛为指向 `README.md` 的最小中文入口，避免双份说明继续分叉。
- 保留代码标识、API、命令、协议名、文件名和上游专有名词的原始拼写。
- 保持演奏分析链路、持久化边界和验证结论不变，不借语言整理改写产品事实。

## 覆盖缺口

- 原归档未包含 `.git`，无法验证原始源码提交，也无法从上一次外部生成提交计算精确差分。
- 本次只整理文档语言，未运行 `xcodebuild test`、visionOS Simulator 或 Apple Vision Pro 真机验证。
- `python_backend/aria/README.md` 属于上游 Aria 项目说明，保留其原始英文，避免维护一份会漂移的本地翻译。
