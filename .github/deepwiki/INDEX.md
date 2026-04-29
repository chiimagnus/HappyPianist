# Deepwiki 索引（LonelyPianist）

本索引是 `.github/deepwiki/` 的入口。目标是让读者先看业务，再看实现；或者先看工程，再落到模块。当前 wiki 已覆盖 macOS、visionOS、Python Dialogue 服务、manual-only Swift Quality workflow，以及 AVP 光柱式 AR 练习引导。

## 推荐阅读路径

### business-first
1. [business-context.md](business-context.md)
2. [overview.md](overview.md)
3. [architecture.md](architecture.md)
4. [data-flow.md](data-flow.md)
5. [modules/lonelypianist-avp.md](modules/lonelypianist-avp.md)
6. [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md)
7. [modules/lonelypianist-macos.md](modules/lonelypianist-macos.md)
8. [modules/piano-dialogue-server.md](modules/piano-dialogue-server.md)
9. [testing.md](testing.md)
10. [troubleshooting.md](troubleshooting.md)

### engineering-first
1. [overview.md](overview.md)
2. [architecture.md](architecture.md)
3. [dependencies.md](dependencies.md)
4. [configuration.md](configuration.md)
5. [data-flow.md](data-flow.md)
6. [testing.md](testing.md)
7. [workflow.md](workflow.md)
8. [modules/lonelypianist-macos-runtime.md](modules/lonelypianist-macos-runtime.md)
9. [modules/lonelypianist-avp-musicxml.md](modules/lonelypianist-avp-musicxml.md)
10. [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md)
11. [modules/piano-dialogue-server-inference.md](modules/piano-dialogue-server-inference.md)

### ci-first
1. [testing.md](testing.md)
2. [workflow.md](workflow.md)
3. [configuration.md](configuration.md)
4. [architecture.md](architecture.md#github-actions-架构)
5. [troubleshooting.md](troubleshooting.md)

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

### macOS 主应用
- [modules/lonelypianist-macos.md](modules/lonelypianist-macos.md)
- [modules/lonelypianist-macos-runtime.md](modules/lonelypianist-macos-runtime.md)
- [modules/lonelypianist-macos-mapping.md](modules/lonelypianist-macos-mapping.md)
- [modules/lonelypianist-macos-recording.md](modules/lonelypianist-macos-recording.md)
- [modules/lonelypianist-macos-dialogue.md](modules/lonelypianist-macos-dialogue.md)

### visionOS 原型
- [modules/lonelypianist-avp.md](modules/lonelypianist-avp.md)
- [modules/lonelypianist-avp-library.md](modules/lonelypianist-avp-library.md)
- [modules/lonelypianist-avp-calibration.md](modules/lonelypianist-avp-calibration.md)
- [modules/lonelypianist-avp-musicxml.md](modules/lonelypianist-avp-musicxml.md)
- [modules/lonelypianist-avp-tracking.md](modules/lonelypianist-avp-tracking.md)
- [modules/lonelypianist-avp-practice.md](modules/lonelypianist-avp-practice.md)
- [modules/lonelypianist-avp-practice-audio.md](modules/lonelypianist-avp-practice-audio.md)

### Python 对话服务
- [modules/piano-dialogue-server.md](modules/piano-dialogue-server.md)
- [modules/piano-dialogue-server-protocol.md](modules/piano-dialogue-server-protocol.md)
- [modules/piano-dialogue-server-inference.md](modules/piano-dialogue-server-inference.md)
- [modules/piano-dialogue-server-debug.md](modules/piano-dialogue-server-debug.md)

### CI / 自动化
- [testing.md](testing.md)
- [workflow.md](workflow.md)
- [configuration.md](configuration.md)
- `.github/workflows/swift-quality.yml`：manual-only SwiftFormat / SwiftLint autocorrect

### 术语与元数据
- [glossary.md](glossary.md)
- [Fallbacks.md](Fallbacks.md)
- [GENERATION.md](GENERATION.md)

## 按问题导航
- **想先理解产品在做什么**：先看 `business-context.md`。
- **要改 macOS 监听 / 映射 / 录音 / 对话**：看 `modules/lonelypianist-macos.md`，再下钻对应子页。
- **要改 AVP 导入 / 校准 / 练习 / MusicXML**：看 `modules/lonelypianist-avp.md`，再下钻对应子页。
- **要改 AR 引导光柱**：看 `modules/lonelypianist-avp-practice.md` 和 `PianoGuideOverlayController`。
- **要改 Python 协议或采样逻辑**：看 `modules/piano-dialogue-server.md` 与 `modules/piano-dialogue-server-inference.md`。
- **要运行测试**：看 `testing.md` 和 `workflow.md`，所有测试需要手动在本地运行。
- **要手动格式化 / lint**：看 `configuration.md` 中的 Swift Quality workflow。
- **遇到运行异常**：从 `troubleshooting.md` 开始。

## 当前自动化事实
| 自动化 | 当前状态 | 备注 |
| --- | --- | --- |
| PR Tests | 已移除 | 原 `pr-tests.yml` workflow 已删除 |
| macOS tests | 本地运行 | 需要手动通过 Xcode 运行 `LonelyPianist` scheme 测试 |
| AVP tests | 本地运行 | 需要手动通过 Xcode 运行 `LonelyPianistAVP` scheme 测试 |
| Swift Quality | 已存在 | 只手动触发；不会因 PR 或 push 自动运行 |
| Python CI | 未接入 | 仍依赖本地 smoke scripts |

## Coverage Gaps / Missing Assets
- PR Tests workflow 已删除，macOS 和 AVP 测试需手动在本地运行。
- Python smoke tests 尚未纳入 GitHub Actions。
- 尚无统一发布流水线，也没有三端 E2E 自动化门禁。
- AVP simulator tests 已跑通，但仍不能替代 Vision Pro 真机上的手部追踪、空间感和光柱视觉舒适度验证。
- `.github/deepwiki/assets/` 保留为资产位，但本次没有额外图片资产可复制。

## 更新记录（Update Notes）
- 2026-04-25: 更新索引以反映 PR-only split tests、manual-only Swift Quality、AVP simulator tests 跑通和光柱式 AR 引导。
- 2026-04-26: 修复模块页内部链接断链；补齐 `.github/deepwiki/assets/` 占位；刷新 `GENERATION.md` 的 commit/branch/时间；同步 Step 1 校准引导式流程文档。
- 2026-04-26: 同步 Step 1 校准的 A0/C8 手势分工、reticle 稳定阈值（5mm）、完成页”重新校准”入口与沉浸空间 overlay 精简。
- 2026-04-28: 反映 pr-tests.yml workflow 已删除；新增 Fallbacks.md 专题页面；更新自动化事实和 Coverage Gaps。
- 2026-04-29: 同步 Step 3 进入不自动开始（`ready` -> 点击下一步才开始）与音频识别 stop 日志降噪；扩充 AVP 音频排障入口。
