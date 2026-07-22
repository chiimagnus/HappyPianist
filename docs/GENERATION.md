# 文档同步元数据

## 本次运行

| 项目 | 值 |
| --- | --- |
| 仓库来源 | 当前 Git 工作树 |
| 源提交 | `5d80709261f9bab9770d0ff0429f380cf1d43c19` |
| 本地同步基线 | `4da55f10`（上一份完整文档同步） |
| 生成时间 | 2026-07-22T16:39:51Z |
| 输出语言 | 中文 |
| 同步方式 | 使用 `neat-freak` 对齐当前源码、Xcode 配置、CI 配置与 canonical 文档 |

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

- 对齐当前工程 target、Swift 版本、RealityKit 内容包工具版本与手动 CI 的实际配置。
- 记录钢琴准备与练习视图当前的目录边界，移除已过期的文件组织假设。
- 保留代码标识、API、命令、协议名、文件名和上游专有名词的原始拼写。
- 保持演奏分析链路、持久化边界和验证结论不变；本次代码变更仅涉及文件重组。

## 覆盖缺口

- 旧归档记录的 `dcb1c4753e63662656997ef48f5e9d1d103c99f7` 不在当前 Git 对象中；本次以 `4da55f10` 到 `HEAD` 的可用历史作为同步差分。
- 未运行 `xcodebuild test`、visionOS Simulator 或 Apple Vision Pro 真机验证；本次只核对源码路径、Xcode/CI 配置与文档链接。
- `python_backend/aria/README.md` 属于上游 Aria 项目说明，保留其原始英文，避免维护一份会漂移的本地翻译。
