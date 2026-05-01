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
| 验证 | 跑对应用例和脚本 | 测试结果 | 本地 macOS/AVP tests + Python smoke |
| 同步 | 更新 deepwiki / README | 知识层 | INDEX 和 Coverage Gaps 同步 |
| 质量维护 | 手动运行 formatter/linter | bot commit 或 no-op | Swift Quality workflow |

## 按运行面修改
| 运行面 | 默认入口 | 常见联动 | 本地验证 |
| --- | --- | --- | --- |
| macOS | `LonelyPianist/ViewModels/LonelyPianistViewModel.swift` | MIDI service、storage、Dialogue | macOS tests |
| visionOS | `LonelyPianistAVP/ViewModels/ARGuideViewModel.swift` + `ViewModels/Library/SongLibraryViewModel.swift` | tracking、musicxml、playback、RealityKit overlay | AVP tests |
| Python | `piano_dialogue_server/server/main.py` + `inference.py` | protocol、debug artifacts | 本地 smoke，暂未自动 CI |
| CI | `.github/workflows/swift-quality.yml` | SwiftFormat + SwiftLint | 手动触发 |

## GitHub Actions 工作流
| Workflow | 自动触发 | 手动触发 | 用途 |
| --- | --- | --- | --- |
| `Swift Quality` | 否 | 是，`workflow_dispatch` | SwiftFormat + SwiftLint autocorrect |

Swift Quality 不会在 PR 自动触发。这个设计是有意的：格式化和 lint autocorrect 应由维护者手动触发并审查 bot commit。

## 测试运行方式
| 改动类型 | 本地运行测试 | CI 验证 |
| --- | --- | --- |
| macOS app/test | `xcodebuild test -scheme LonelyPianist -destination 'platform=macOS'` | 无（pr-tests.yml 已删除） |
| AVP app/test | `xcodebuild test -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,name=Apple Vision Pro'` | 无（pr-tests.yml 已删除） |
| RealityKitContent | AVP tests | 无（pr-tests.yml 已删除） |
| Xcode project | macOS + AVP tests | 无（pr-tests.yml 已删除） |

## 常见变更清单
| 变更 | 需要同步 | 推荐验证 |
| --- | --- | --- |
| Dialogue 协议字段 | Swift model + WebSocket service + Python protocol | macOS tests + Python WS smoke |
| 曲库字段 | SongLibrary models + store + seeder | AVP library tests |
| 校准字段 | StoredWorldAnchorCalibration + store + localization | AVP calibration tests |
| MusicXML 规则 | parser + step builder + practice view model | MusicXML parser/timeline tests |
| AR 贴皮高亮样式 | `PianoGuideOverlayController` + practice docs | AVP tests + Vision Pro 手工观察 |
| Xcode target / package | project + scheme + workflow runner | macOS + AVP tests |
| SwiftFormat/SwiftLint 规则 | `.swiftformat` / `.swiftlint.yml` | 手动 Swift Quality |

## CI 调试流程
| 现象 | 先看哪里 | 常见处理 |
| --- | --- | --- |
| Package graph resolve 失败 | Xcode build 日志 | 确认依赖版本和 Swift tools 版本 |
| 找不到 scheme | `xcodebuild -list` | 检查 shared scheme / project 文件 |
| 找不到 AVP destination | `xcodebuild -showdestinations` | 调整 `platform=visionOS Simulator,name=Apple Vision Pro` |
| macOS compile failed | `SwiftCompile` 第一条 error | 修源码 |
| AVP test 运行很久 | 本地测试输出 | visionOS simulator 启动慢属预期 |
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
| `main` | 默认分支 | Swift Quality workflow 手动触发可用于代码质量维护 |
| feature branches | 功能开发 | PR 到 `main` 后需要手动运行本地测试 |
| deepwiki update commits | 文档更新 | 只改 `.github/deepwiki/**` 时不会触发 Swift Quality |

## Coverage Gaps
- 没有统一发布流水线；因此本页只记录开发、验证和文档同步路径。
- Python smoke tests 仍未进入 GitHub Actions。
- PR Tests workflow 已删除，自动化测试需要在本地手动运行。

## 更新记录（Update Notes）
- 2026-04-25: 更新 PR-only split tests、manual-only Swift Quality、CI 调试流程和 AVP 光柱变更清单。
- 2026-04-28: 反映 pr-tests.yml workflow 已删除，测试需要手动在本地运行。
- 2026-05-01: 同步 AVP Practice 的 RealityKit 引导从光柱迁移为琴键贴皮高亮（decal），并移除 correct/wrong feedback 与 immersive pulse。
