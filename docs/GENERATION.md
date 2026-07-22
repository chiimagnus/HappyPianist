# 文档同步元数据

## 本次运行

| 项目 | 值 |
| --- | --- |
| 仓库来源 | 当前 Git 工作树 |
| 源提交 | `4399a0342ecf4b6d57e4410c0a9949ea52c53280` |
| 本地同步基线 | `4399a034`（上一份完整文档同步） |
| 生成时间 | 2026-07-22T16:43:21Z |
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
- 记录根目录 Makefile 作为本地与 CI 的 build/test/run 入口；CI 动态注入 Simulator UDID，Makefile 内部调用原生 `xcodebuild`。
- 保留代码标识、API、命令、协议名、文件名和上游专有名词的原始拼写。
- 保持演奏分析链路、持久化边界和验证结论不变；本次代码变更仅涉及文件重组。

## 覆盖缺口

- 未运行完整 `xcodebuild test`、visionOS Simulator 或 Apple Vision Pro 真机验证；本次只运行 `make help` / `make -n test`，并核对 Makefile、Xcode/CI 配置与文档链接。
- `python_backend/aria/README.md` 属于上游 Aria 项目说明，保留其原始英文，避免维护一份会漂移的本地翻译。
