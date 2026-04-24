# 工作流

## 进入仓库的判断顺序
1. 先判断改动属于 macOS / visionOS / Python / CI 哪一面。
2. 再找对应入口：App、ViewModel、Service、Test、Workflow。
3. 涉及 Dialogue 先确认 `piano_dialogue_server` 已启动。
4. 涉及 AVP 先确认 Step 1 校准和 Step 2 曲库是否就绪。
5. 涉及 CI 先判断是 PR 自动测试，还是手动 Swift Quality。

## 开发循环
| 阶段 | 做什么 | 产物 | 验证 |
| --- | --- | --- | --- |
| 定位 | 锁定业务和模块边界 | 变更范围 | 阅读 deepwiki + 搜索代码 |
| 实现 | 按 MVVM + Services 改代码 | 代码变更 | 本地 build/test |
| 验证 | 跑对应用例和脚本 | 测试结果 | PR Tests / Python smoke |
| 同步 | 更新 deepwiki / README | 知识层 | INDEX 和 Coverage Gaps 同步 |
| 质量维护 | 手动运行 formatter/linter | bot commit 或 no-op | Swift Quality workflow |

## 按运行面修改
| 运行面 | 默认入口 | 常见联动 | PR 自动验证 |
| --- | --- | --- | --- |
| macOS | `LonelyPianist/ViewModels/LonelyPianistViewModel.swift` | MIDI service、storage、Dialogue | macOS tests |
| visionOS | `LonelyPianistAVP/ViewModels/ARGuideViewModel.swift` + `ViewModels/Library/SongLibraryViewModel.swift` | tracking、musicxml、playback、RealityKit overlay | AVP tests |
| Python | `piano_dialogue_server/server/main.py` + `inference.py` | protocol、debug artifacts | 本地 smoke，暂未自动 CI |
| CI | `.github/workflows/pr-tests.yml` / `swift-quality.yml` | path filters、runner、xcodebuild command | 修改 PR Tests 会触发两侧 Xcode tests |

## GitHub Actions 工作流
| Workflow | 自动触发 | 手动触发 | 用途 |
| --- | --- | --- | --- |
| `PR Tests` | 仅 `pull_request` 且路径匹配 | 否 | 自动跑 macOS/AVP Xcode tests |
| `Swift Quality` | 否 | 是，`workflow_dispatch` | SwiftFormat + SwiftLint autocorrect |

PR Tests 不会在普通 push 自动触发；Swift Quality 不会在 PR 自动触发。这个分离是有意设计：测试应该自动给 PR 反馈，格式化和 lint autocorrect 应由维护者手动触发并审查 bot commit。

## PR 测试分流
| 改动类型 | 匹配路径 | 自动跑什么 |
| --- | --- | --- |
| macOS app/test | `LonelyPianist/**`, `LonelyPianistTests/**` | `macOS tests` |
| AVP app/test | `LonelyPianistAVP/**`, `LonelyPianistAVPTests/**` | `AVP tests` |
| RealityKitContent | `Packages/RealityKitContent/**` | `AVP tests` |
| Xcode project | `LonelyPianist.xcodeproj/**` | macOS + AVP tests |
| PR workflow | `.github/workflows/pr-tests.yml` | macOS + AVP tests |
| Swift quality workflow | `.github/workflows/swift-quality.yml` | 不由 PR Tests 自动匹配，必要时手动检查 |

## 常见变更清单
| 变更 | 需要同步 | 推荐验证 |
| --- | --- | --- |
| Dialogue 协议字段 | Swift model + WebSocket service + Python protocol | macOS tests + Python WS smoke |
| 曲库字段 | SongLibrary models + store + seeder | AVP library tests |
| 校准字段 | StoredWorldAnchorCalibration + store + localization | AVP calibration tests |
| MusicXML 规则 | parser + step builder + practice view model | MusicXML parser/timeline tests |
| AR 光柱样式 | `PianoGuideOverlayController` + practice docs | AVP tests + Vision Pro 手工观察 |
| Xcode target / package | project + scheme + workflow runner | macOS + AVP PR Tests |
| SwiftFormat/SwiftLint 规则 | `.swiftformat` / `.swiftlint.yml` | 手动 Swift Quality |

## CI 调试流程
| 现象 | 先看哪里 | 常见处理 |
| --- | --- | --- |
| Package graph resolve 失败 | `Resolve Package Graph` 日志 | 确认 runner 是 `macos-26`，满足 Swift tools 6.2 |
| 找不到 scheme | `xcodebuild -list` 步骤 | 检查 shared scheme / project 文件 |
| 找不到 AVP destination | `xcodebuild -showdestinations` 本地或临时 CI 步骤 | 调整 `platform=visionOS Simulator,name=Apple Vision Pro` |
| macOS compile failed | `SwiftCompile` 第一条 error | 修源码，不要先改 workflow |
| AVP test 运行很久 | `Run AVP tests` 步骤 | visionOS simulator 启动慢属预期；若长期不稳可拆 build-for-testing |
| Swift Quality 产生大 diff | bot commit diff | 审查 formatter/lint 改动后再合并 |

## 维护 deepwiki
- 业务变化先改 `business-context.md`。
- 技术边界变化再改 `architecture.md`、`data-flow.md`。
- 配置变化改 `configuration.md`。
- 测试命中面变化改 `testing.md`。
- CI/协作流程变化改本页。
- 新增运行面时新增 module page，并补 `INDEX.md`。
- 更新 `GENERATION.md` 记录 commit、branch、页面清单和 Coverage Gaps。

## 发布与分支
| 分支 / PR | 角色 | 注意事项 |
| --- | --- | --- |
| `main` | 默认分支 | workflow 在这里生效后，后续 PR 才会自动跑对应 Actions |
| feature branches | 功能开发 | PR 到 `main` 后由 PR Tests 自动分流 |
| deepwiki update commits | 文档更新 | 只改 `.github/deepwiki/**` 时不会触发 PR Tests，除非 workflow 路径也变更 |

## Coverage Gaps
- 没有统一发布流水线；因此本页只记录开发、验证和文档同步路径。
- Python smoke tests 仍未进入 GitHub Actions。

## 更新记录（Update Notes）
- 2026-04-25: 更新 PR-only split tests、manual-only Swift Quality、CI 调试流程和 AVP 光柱变更清单。
