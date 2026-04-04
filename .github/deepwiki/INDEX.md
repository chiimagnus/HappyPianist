# LonelyPianist Deepwiki INDEX

## 仓库总览

本知识库目标是让读者在不直接通读源码的情况下，建立对 `LonelyPianist` 的完整可修改心智模型：

- 先理解产品语义与用户旅程。
- 再定位运行时边界、数据流、配置和风险点。
- 最后按模块页进入具体改动区域。

## 推荐阅读路径

### business-first（业务入口优先）

1. [business-context.md](business-context.md)
2. [overview.md](overview.md)
3. [data-flow.md](data-flow.md)
4. [architecture.md](architecture.md)
5. [modules/mapping-engine.md](modules/mapping-engine.md)
6. [modules/recording-playback.md](modules/recording-playback.md)
7. [troubleshooting.md](troubleshooting.md)

### engineering-first（工程入口优先）

1. [overview.md](overview.md)
2. [architecture.md](architecture.md)
3. [dependencies.md](dependencies.md)
4. [configuration.md](configuration.md)
5. [testing.md](testing.md)
6. [workflow.md](workflow.md)
7. [modules/lonelypianist-app.md](modules/lonelypianist-app.md)

## 核心页面

- [business-context.md](business-context.md) — 产品定位、用户旅程与业务规则入口。
- [overview.md](overview.md) — 仓库地图、运行面与入口点。
- [architecture.md](architecture.md) — 组件边界、依赖方向与扩展点。
- [dependencies.md](dependencies.md) — 技术栈、包、系统接口与兼容约束。
- [data-flow.md](data-flow.md) — 事件/状态/存储/回放主链路。
- [configuration.md](configuration.md) — 运行与构建配置、权限与误配。
- [testing.md](testing.md) — 自动化/手测策略与回归重点。
- [workflow.md](workflow.md) — 开发协作与文档同步流程。
- [glossary.md](glossary.md) — 统一术语定义。

## 模块页面

- [modules/lonelypianist-app.md](modules/lonelypianist-app.md)
- [modules/mapping-engine.md](modules/mapping-engine.md)
- [modules/recording-playback.md](modules/recording-playback.md)
- [modules/menubardockkit.md](modules/menubardockkit.md)

## 专题页面

- [troubleshooting.md](troubleshooting.md)
- [operations.md](operations.md)
- [release.md](release.md)
- [security.md](security.md)
- [storage.md](storage.md)

## 外部集成页面

- [integrations/macos-system-interfaces.md](integrations/macos-system-interfaces.md)

## 参考与元数据

- [references/开发规范.md](references/开发规范.md)
- [GENERATION.md](GENERATION.md)

## Coverage Gaps / Missing Assets

- 目前未发现仓库内 CI workflow 文件（`.github/workflows` 为空）。
- 目前 `assets/` 目录尚无图像资产，仅保留目录占位。
- 未发现自动化发布流水线与公证脚本证据。
