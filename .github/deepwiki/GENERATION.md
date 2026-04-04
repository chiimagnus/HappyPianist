# Deepwiki Generation Metadata

## Generation Summary

- Repository: `LonelyPianist`
- Branch: `crh`
- Commit: `130d519dbab1a21269011e7a5cd92b54615f637e`
- Generation timestamp (local): `2026-03-29 01:19:33 +0800`
- Output language: `Chinese (zh-CN)`
- Generation mode: `Incremental sync update`

## Page Inventory

### Index & Metadata

- `.github/deepwiki/INDEX.md`
- `.github/deepwiki/GENERATION.md`

### Core Pages

- `.github/deepwiki/business-context.md`
- `.github/deepwiki/overview.md`
- `.github/deepwiki/architecture.md`
- `.github/deepwiki/dependencies.md`
- `.github/deepwiki/data-flow.md`
- `.github/deepwiki/configuration.md`
- `.github/deepwiki/testing.md`
- `.github/deepwiki/workflow.md`
- `.github/deepwiki/glossary.md`

### Module Pages

- `.github/deepwiki/modules/lonelypianist-app.md`
- `.github/deepwiki/modules/mapping-engine.md`
- `.github/deepwiki/modules/recording-playback.md`
- `.github/deepwiki/modules/menubardockkit.md`

### Topic Pages

- `.github/deepwiki/troubleshooting.md`
- `.github/deepwiki/operations.md`
- `.github/deepwiki/release.md`
- `.github/deepwiki/security.md`
- `.github/deepwiki/storage.md`

### Integration & Reference Pages

- `.github/deepwiki/integrations/macos-system-interfaces.md`
- `.github/deepwiki/references/开发规范.md`

## Copied Asset List

- No copied binary/image assets in this generation.
- Assets directory reserved: `.github/deepwiki/assets/`

## Update Notes

- 2026-03-29：同步 deepwiki 元数据到当前 `crh` 分支最新提交，并确认文档内容与仓库最新结构一致（移除 CLI 运行面、补齐 MIDI 输出与回放路由、补齐开发脚本入口）。
- 2026-03-29：补齐 `.github/scripts/midi-send-test.swift` 的参数用法说明（`--dest` / `--match`）与“单 destination 自动选择”的行为细节。
- 2026-03-29：将 `dependencies.md` / `release.md` 中的分支与 commit 真值源统一指向 `GENERATION.md`，避免多页面写死导致漂移。
- 2026-03-29：移除 `release.md` 中硬编码的版本示例值，避免与 `configuration.md`（引用 `project.pbxproj`）的单一事实源冲突。

- Replaced legacy business entry doc by adding `business-context.md` as正式入口层。
- Migrated `.github/docs/开发规范.md` to `.github/deepwiki/references/开发规范.md`.
- Deleted legacy `.github/docs/business-logic.md` as requested.
- Cleaned up the stale command-line module page and related references because this repository no longer contains an independent command-line implementation.

## Validation Checklist

- [x] 核心页面全部存在
- [x] `business-context.md` 作为业务入口并路由技术页
- [x] 每条主要产品线至少一个模块页
- [x] 所有页面已进入 `INDEX.md`
- [x] 覆盖配置/测试/工作流/排障/安全/发布主题
- [x] 显式记录 Coverage Gaps
