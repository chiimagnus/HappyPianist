# Deepwiki Generation Metadata

## Generation Summary

- Repository: `PianoKey`
- Branch: `crh`
- Commit: `228d32deee961c17dc0a7c561f90e7753182e805`
- Generation timestamp (local): `2026-03-23 00:05:04 +0800`
- Output language: `Chinese (zh-CN)`
- Generation mode: `Initial generation`

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

- `.github/deepwiki/modules/pianokey-app.md`
- `.github/deepwiki/modules/mapping-engine.md`
- `.github/deepwiki/modules/recording-playback.md`
- `.github/deepwiki/modules/menubardockkit.md`
- `.github/deepwiki/modules/pianokey-cli.md`

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

- Replaced legacy business entry doc by adding `business-context.md` as正式入口层。
- Migrated `.github/docs/开发规范.md` to `.github/deepwiki/references/开发规范.md`.
- Deleted legacy `.github/docs/business-logic.md` as requested.

## Validation Checklist

- [x] 核心页面全部存在
- [x] `business-context.md` 作为业务入口并路由技术页
- [x] 每条主要产品线至少一个模块页
- [x] 所有页面已进入 `INDEX.md`
- [x] 覆盖配置/测试/工作流/排障/安全/发布主题
- [x] 显式记录 Coverage Gaps
