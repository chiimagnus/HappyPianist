# Deepwiki 索引（LonelyPianist）

本索引为 `.github/deepwiki/` 的入口。目标是让读者在不直接翻源码的前提下，先理解产品语义，再定位到可改动的技术细节页。

## 推荐阅读路径

### business-first（先业务后技术）
1. [business-context.md](business-context.md)
2. [overview.md](overview.md)
3. [data-flow.md](data-flow.md)
4. [modules/lonelypianist-macos.md](modules/lonelypianist-macos.md)
5. [modules/lonelypianist-avp.md](modules/lonelypianist-avp.md)
6. [modules/piano-dialogue-server.md](modules/piano-dialogue-server.md)

### engineering-first（先架构后模块）
1. [overview.md](overview.md)
2. [architecture.md](architecture.md)
3. [dependencies.md](dependencies.md)
4. [configuration.md](configuration.md)
5. [testing.md](testing.md)
6. [workflow.md](workflow.md)
7. [troubleshooting.md](troubleshooting.md)

## 页面分组

### 入口与核心理解
- [business-context.md](business-context.md)
- [overview.md](overview.md)
- [architecture.md](architecture.md)
- [data-flow.md](data-flow.md)

### 工程基线
- [dependencies.md](dependencies.md)
- [configuration.md](configuration.md)
- [storage.md](storage.md)
- [testing.md](testing.md)
- [workflow.md](workflow.md)
- [troubleshooting.md](troubleshooting.md)

### 模块页（按运行面）
- [modules/lonelypianist-macos.md](modules/lonelypianist-macos.md)
- [modules/lonelypianist-avp.md](modules/lonelypianist-avp.md)
- [modules/piano-dialogue-server.md](modules/piano-dialogue-server.md)

### 术语与元数据
- [glossary.md](glossary.md)
- [GENERATION.md](GENERATION.md)

## 按问题导航
- **我想快速理解这个产品在做什么**：先看 `business-context.md`。
- **我准备改某个功能**：先看 `architecture.md`，再跳对应 `modules/*.md`。
- **我在排故障**：从 `troubleshooting.md` 开始，必要时回到 `data-flow.md`。
- **我在配置环境**：先看 `configuration.md`，再看 `dependencies.md`。

## Coverage Gaps / Missing Assets
- 当前仓库未见 `.github/workflows/*`，CI 门禁链路仅能描述为本地实践。
- `assets/` 目录已保留，但本次未复制新增图像资产（核心图表使用 Mermaid 内联）。
