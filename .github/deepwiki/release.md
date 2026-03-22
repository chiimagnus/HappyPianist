# 发布

## 发布资产

| 资产 | 位置 | 版本字段来源 | 发布形态 |
| --- | --- | --- | --- |
| PianoKey App | `PianoKey.xcodeproj` target `PianoKey` | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` | macOS 应用构建产物 |
| PianoKeyCLI | `Packages/PianoKeyCLI` | Swift package manifest + git tag（约定） | CLI 可执行文件 |
| MenuBarDockKit | `Packages/MenuBarDockKit` | Swift package manifest + git tag（约定） | Swift library |

## 版本真值与策略

| 维度 | 真值来源 | 当前观察值 |
| --- | --- | --- |
| App Marketing Version | `configuration.md`（引用 `project.pbxproj`） | 见配置页单一事实源 |
| App Build Number | `configuration.md`（引用 `project.pbxproj`） | 见配置页单一事实源 |
| 分支 | Git | `crh` |
| Commit | Git | `228d32deee961c17dc0a7c561f90e7753182e805` |

## 建议发布流程（当前仓库推断）

1. 更新版本字段（如需发版）。
2. 执行本地构建与关键回归（权限、映射、录制、回放）。
3. 准备 release note（含已知限制与回滚方案）。
4. 生成并签名分发产物（具体渠道流程需团队补充）。

## 构建与验证清单

| 检查项 | 命令 / 动作 | 通过标准 |
| --- | --- | --- |
| App 构建 | `xcodebuild ... -scheme PianoKey build` | 无编译错误 |
| 单元测试 | `xcodebuild ... -scheme PianoKeyTests test` | 关键测试通过 |
| CLI 构建 | `swift build --package-path Packages/PianoKeyCLI` | 构建成功 |
| CLI 渲染 | `swift run ... render --json` | 返回 `ok: true` |

## 回滚与应急

- App 回滚：回退到上一稳定 commit，重新构建并验证权限/映射链路。
- 数据层回滚：若涉及 SwiftData schema 变更，需确保兼容旧数据或提供迁移脚本。
- CLI 回滚：保持上一版可执行文件可复用。

## 发布风险点

1. 权限相关行为变化会直接影响“看似可用但实际无输出”体验。
2. 回放引擎变更可能影响 Recorder 可用性。
3. 主工程部署目标与 package 平台要求不一致时可能触发构建问题。

## 示例片段

```text
// PianoKey.xcodeproj/project.pbxproj
MARKETING_VERSION = 1.0;
CURRENT_PROJECT_VERSION = 1;
PRODUCT_BUNDLE_IDENTIFIER = com.chiimagnus.PianoKey;
```

```bash
# CLI release smoke
swift build --package-path Packages/PianoKeyCLI
swift run --package-path Packages/PianoKeyCLI pianokey-cli render --input ./song.mid --output ./song.wav --json
```

## Coverage Gaps（如有）

- 仓库内缺少 `.github/workflows` 与正式发布流水线定义。
- 缺少 notarization / distribution 渠道的明确脚本与文档。

## 来源引用（Source References）

- `PianoKey.xcodeproj/project.pbxproj`
- `AGENTS.md`
- `README.md`
- `Packages/PianoKeyCLI/Package.swift`
- `Packages/PianoKeyCLI/README.md`
- `Packages/PianoKeyCLI/Sources/PianoKeyCLI/main.swift`
- `Packages/MenuBarDockKit/Package.swift`
