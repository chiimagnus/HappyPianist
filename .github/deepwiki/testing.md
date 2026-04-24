# 测试

## 测试策略
| 维度 | 方法 | 目标 | CI 状态 |
| --- | --- | --- | --- |
| macOS 逻辑 | Swift Testing + `xcodebuild test` | mapping / recorder / dialogue / MIDI 编译回归 | PR 自动触发，已跑通 |
| AVP 逻辑 | Swift Testing + visionOS simulator | MusicXML / calibration / practice / library / RealityKitContent | PR 自动触发，已跑通，耗时较长 |
| Python 自检 | 脚本 + WS client | 模型生成与协议回环 | 本地手动 |
| Swift quality | SwiftFormat + SwiftLint | 格式化和 lint autocorrect | GitHub Actions 手动触发 |

## GitHub Actions 测试门禁
| Workflow | 触发 | 做什么 |
| --- | --- | --- |
| `PR Tests` | `pull_request` 且路径匹配 | 先检测 macOS / AVP 路径，再按需运行对应 Xcode tests |
| `Swift Quality` | `workflow_dispatch` | 手动运行 SwiftFormat / SwiftLint fix，并在有变更时提交 |

`PR Tests` 是自动验证门禁；`Swift Quality` 是手动维护工具。两者不要合并成同一个自动流程，否则 formatter 可能在 PR 上自动推 commit。

## 命令
| 命令 | 适用场景 |
| --- | --- |
| `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianist -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | macOS 回归 |
| `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,name=Apple Vision Pro' CODE_SIGNING_ALLOWED=NO` | AVP 回归，GitHub Actions 上使用 `macos-26` |
| `xcodebuild -list -project LonelyPianist.xcodeproj` | 检查 scheme 是否被 CI 识别 |
| `xcodebuild -showdestinations -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP` | AVP destination 诊断 |
| `cd piano_dialogue_server && python scripts/test_generate.py` | 离线推理 sanity check |
| `cd piano_dialogue_server/server && ../.venv/bin/python test_client.py` | WS 回环 |
| `curl -s http://127.0.0.1:8765/health` | 服务健康检查 |
| `swiftformat --config .swiftformat LonelyPianist LonelyPianistAVP LonelyPianistTests LonelyPianistAVPTests` | 手动格式化 |
| `swiftlint lint --config .swiftlint.yml` | 手动 lint |

## PR Tests 路径分流
| 改动路径 | 触发 job | 说明 |
| --- | --- | --- |
| `LonelyPianist/**` | macOS tests | 主 app 代码变更 |
| `LonelyPianistTests/**` | macOS tests | macOS test 变更 |
| `LonelyPianistAVP/**` | AVP tests | visionOS app 代码变更 |
| `LonelyPianistAVPTests/**` | AVP tests | AVP test 变更 |
| `Packages/RealityKitContent/**` | AVP tests | RealityKitContent 使用 Swift tools 6.2 |
| `LonelyPianist.xcodeproj/**` | macOS + AVP tests | project 设置可能影响两个 target |
| `.github/workflows/pr-tests.yml` | macOS + AVP tests | 测试门禁自身变更需自验证 |

## 关键测试分布
| 区域 | 代表测试 |
| --- | --- |
| macOS mapping | `LonelyPianistTests/Mapping/UnifiedMappingConfigTests.swift` |
| macOS recorder | `LonelyPianistTests/Recording/DefaultRecordingServiceTests.swift` |
| macOS silence | `LonelyPianistTests/SilenceDetectionServiceTests.swift` |
| AVP library | `SongLibraryIndexStoreTests.swift`, `SongFileStoreTests.swift`, `AudioImportServiceTests.swift` |
| AVP calibration | `WorldAnchorCalibrationStoreTests.swift`, `CalibrationPointCaptureServiceTests.swift` |
| AVP practice | `PracticeSessionViewModelTests.swift`, `PracticeLocalizationPolicyTests.swift`, `StepMatcherTests.swift` |
| MusicXML parser | `MusicXMLParser*.swift`, `MXLReaderTests.swift`, `MusicXML*TimelineTests.swift` |
| Python | `scripts/test_generate.py`, `scripts/test_infilling.py`, `server/test_client.py` |

## 覆盖重点
| 风险区 | 为什么要测 | 推荐验证 |
| --- | --- | --- |
| 速度阈值和和弦严格相等 | 直接影响映射触发 | macOS tests |
| 录音开闭音 | 影响 take 完整性 | macOS recorder tests |
| Dialogue 状态机 | 影响 turn-based 体验 | macOS dialogue tests + Python WS smoke |
| CoreMIDI source refresh | Xcode 26.2 / Swift 6.2 对捕获语义更严格 | macOS compile/test |
| 曲库索引 / 文件一致性 | 影响 Step 2 / Step 3 | AVP library tests |
| 校准和定位失败分支 | 影响沉浸式流程 | AVP calibration / localization tests |
| MusicXML expressivity | 影响练习步骤和 autoplay | MusicXML parser/timeline tests |
| RealityKit 光柱引导 | 影响 Step 3 可见反馈 | AVP tests + Vision Pro 手工观察 |
| GitHub Actions path filters | 影响 PR 是否跑对 job | 修改 workflow 时两边都跑 |

## 手工冒烟
1. macOS 授权 Accessibility，验证 Start Listening、Mapping、Recorder、Dialogue。
2. Python 先跑 `/health`，再跑 `test_client.py`。
3. AVP 导入 MusicXML，完成校准，进入练习并验证光柱、跳步、自动播放。
4. 修改 workflow 后提交 PR，确认 `Detect changed targets`、`macOS tests`、`AVP tests` 的触发符合路径预期。
5. 手动触发 `Swift Quality` 后检查 bot commit diff，确认只有格式化/lint 修复。

## build-for-testing 与 test
| 命令 | 覆盖 | 适用场景 |
| --- | --- | --- |
| `xcodebuild build-for-testing` | 编译 app/test target，生成测试产物，不执行测试 | 当 AVP simulator test 不稳定或太慢时作为轻量 PR gate |
| `xcodebuild test` | 构建并启动 test session，执行 XCTest/Swift Testing | 当前 macOS 和 AVP PR gate |
| `xcodebuild test-without-building` | 复用已构建产物执行测试 | 后续做矩阵 destination 或缓存时考虑 |

当前仓库选择 `xcodebuild test` 作为 PR gate，因为 macOS 和 AVP tests 都已在 GitHub Actions 上跑通。AVP test 约数分钟级，属于预期偏重流程。

## 现状
- `.github/workflows/pr-tests.yml` 已存在，并且只在 PR 时自动触发。
- `.github/workflows/swift-quality.yml` 已存在，并且只允许手动触发。
- macOS tests 和 AVP tests 均使用 `macos-26` 以满足 Xcode 26.2 / Swift 6.2 / visionOS simulator 需求。
- Python tests 暂未纳入 Actions。

## Coverage Gaps
- 三端端到端自动化仍缺失；当前覆盖依赖单测、CI Xcode tests、Python smoke 和人工冒烟组合。
- Python server 的模型权重、设备选择和外部依赖没有稳定 CI 环境。

## 更新记录（Update Notes）
- 2026-04-25: 记录 PR-only split Xcode tests、AVP simulator test 跑通、manual Swift Quality、build-for-testing 与 test 的 CI 取舍。
