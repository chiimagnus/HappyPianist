# Deepwiki 索引（LonelyPianist）

本索引是 `.github/deepwiki/` 的统一入口，目标是：读者只看 wiki 也能快速建立“业务语义 → 技术落点 → 可改动边界”的完整心智模型。

## 推荐阅读路径

### business-first（先业务后实现）
1. [business-context.md](business-context.md)
2. [overview.md](overview.md)
3. [modules/lonelypianist-avp.md](modules/lonelypianist-avp.md)
4. [data-flow.md](data-flow.md)
5. [configuration.md](configuration.md)
6. [troubleshooting.md](troubleshooting.md)

### engineering-first（先架构后模块）
1. [overview.md](overview.md)
2. [architecture.md](architecture.md)
3. [data-flow.md](data-flow.md)
4. [modules/lonelypianist-macos.md](modules/lonelypianist-macos.md)
5. [modules/lonelypianist-avp.md](modules/lonelypianist-avp.md)
6. [modules/piano-dialogue-server.md](modules/piano-dialogue-server.md)
7. [testing.md](testing.md)
8. [workflow.md](workflow.md)

## 页面分组

### 业务入口与全局认知
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
- **想先知道产品到底做什么**：先看 `business-context.md`。
- **要改 AVP 的导入/选曲/练习链路**：先看 `modules/lonelypianist-avp.md`，再看 `data-flow.md`。
- **要改 macOS MIDI 映射/录制/对话**：先看 `modules/lonelypianist-macos.md`。
- **要改 Python 推理协议或服务行为**：先看 `modules/piano-dialogue-server.md`。
- **遇到运行异常**：从 `troubleshooting.md` 开始。

## Coverage Gaps / Missing Assets
- 仓库内仍未发现 `.github/workflows/*`，CI 门禁链路暂无可验证定义。
- `assets/` 目录已补齐，但本次仍未新增外部图片资产（核心图表继续使用 Mermaid 内联）。
- `LonelyPianistAVP` 共享 scheme 文件仍未进入 `xcshareddata/xcschemes`，AVP 命令可用性依赖本地 Xcode 环境。
