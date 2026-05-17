# 测试

## 测试策略
| 维度 | 方法 | 目标 | CI 状态 |
| --- | --- | --- | --- |
| macOS 逻辑 | Swift Testing + `xcodebuild test` | mapping / recorder / dialogue / MIDI 编译回归 | 本地手动运行 |
| AVP 逻辑 | Swift Testing + visionOS simulator | MusicXML / calibration / practice / library / RealityKitContent | 本地手动运行，耗时较长 |
| Python 自检 | 脚本 + WS client | 模型生成与协议回环 | 本地手动 |
| Swift quality | SwiftFormat（可选） | 代码格式化 | 本地手动运行（仓库当前无 CI workflows） |

## 命令
| 命令 | 适用场景 |
| --- | --- |
| `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianist -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | macOS 回归 |
| `xcodebuild -showdestinations -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP` | 获取可用 visionOS simulator destinations（需要 concrete device id） |
| `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,id=<device-id>' CODE_SIGNING_ALLOWED=NO` | AVP 回归（visionOS simulator；避免使用 placeholder destination） |
| `xcodebuild -list -project LonelyPianist.xcodeproj` | 检查 scheme 列表 |
| `cd piano_dialogue_server && python scripts/test_generate.py` | 离线推理 sanity check |
| `cd piano_dialogue_server && ../.venv/bin/python -m server.api.test_client` | WS 回环 |
| `curl -s http://127.0.0.1:8765/health` | 服务健康检查 |
| `curl -X POST http://127.0.0.1:8765/generate -H "Content-Type: application/json" -d '{"type":"generate","protocol_version":1,"notes":[],"params":{"strategy":"deterministic"}}'` | HTTP 生成接口最小验证 |
| `swiftformat --config .swiftformat LonelyPianist LonelyPianistAVP LonelyPianistTests LonelyPianistAVPTests` | 手动格式化 |
| `cd piano_dialogue_server && ./scripts/run_server.sh` | 一键启动 Python 服务（包含依赖安装） |

## 测试运行方式
| 改动路径 | 本地运行测试 | 说明 |
| --- | --- | --- |
| `LonelyPianist/**` | macOS tests | 主 app 代码变更 |
| `LonelyPianistTests/**` | macOS tests | macOS test 变更 |
| `LonelyPianistAVP/**` | AVP tests | visionOS app 代码变更 |
| `LonelyPianistAVPTests/**` | AVP tests | AVP test 变更 |
| `Packages/RealityKitContent/**` | AVP tests | RealityKitContent 使用 Swift tools 6.2 |
| `LonelyPianist.xcodeproj/**` | macOS + AVP tests | project 设置可能影响两个 target |

> 注意：当前仓库未提交 GitHub Actions workflows，所有测试需要手动在本地运行。

## 关键测试分布
| 区域 | 代表测试 |
| --- | --- |
| macOS mapping | `LonelyPianistTests/Mapping/UnifiedMappingConfigTests.swift` |
| macOS recorder | `LonelyPianistTests/Recording/DefaultRecordingServiceTests.swift` |
| macOS silence | `LonelyPianistTests/SilenceDetectionServiceTests.swift` |
| AVP library | `SongLibraryIndexStoreTests.swift`, `SongFileStoreTests.swift`, `AudioImportServiceTests.swift` |
| AVP calibration | `WorldAnchorCalibrationStoreTests.swift`, `CalibrationPointCaptureServiceTests.swift` |
| AVP window navigation | `WindowCoordinatorTests.swift` |
| AVP keyboard geometry | `AppModelKeyboardGeometryTests.swift` |
| AVP practice | `PracticeSessionViewModelTests.swift`, `PracticeLocalizationPolicyTests.swift`, `StepMatcherTests.swift`, `PracticeSessionHandSeparatedMatchingTests.swift` |
| AVP manual advance | `ManualAdvanceStrategyTests.swift` |
| AVP notation | `GrandStaffNotationLayoutServiceTests.swift` |
| AVP hand semantics | `ScoreHandTests.swift`, `PracticeStepBuilderTests.swift`, `PianoHighlightGuideBuilderServiceTests.swift` |
| AVP single-staff routing | `MusicXMLHandRouterTests.swift` |
| AVP improv | `ImprovBackendClientCodingTests.swift`, `PhraseRecorderTests.swift`, `ImprovScheduleBuilderTests.swift` |
| MusicXML parser | `MusicXMLParser*.swift`, `MXLReaderTests.swift`, `MusicXML*TimelineTests.swift` |
| Virtual piano | `VirtualPianoTests.swift` |
| Python | `scripts/test_generate.py`, `scripts/test_infilling.py`, `server/api/test_client.py` |

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
| RealityKit 贴皮高亮引导 | 影响 Step 3 可见引导与对齐 | AVP tests + Vision Pro 手工观察 |

## 手工冒烟
1. macOS 授权 Accessibility，验证 Start Listening、Mapping、Recorder、Dialogue。
2. Python 先跑 `/health`，再跑 `test_client.py`。
3. AVP 导入 MusicXML，完成校准，进入练习并验证贴皮高亮、跳步、自动播放。
4. （可选）本地运行 `swiftformat --config .swiftformat ...`，确认格式化 diff 可控且不影响业务语义。

## build-for-testing 与 test
| 命令 | 覆盖 | 适用场景 |
| --- | --- | --- |
| `xcodebuild build-for-testing` | 编译 app/test target，生成测试产物，不执行测试 | 当 AVP simulator test 不稳定或太慢时作为轻量验证 |
| `xcodebuild test` | 构建并启动 test session，执行 XCTest/Swift Testing | macOS 和 AVP 本地完整测试 |
| `xcodebuild test-without-building` | 复用已构建产物执行测试 | 后续做矩阵 destination 或缓存时考虑 |

当前仓库选择手动运行本地测试，AVP test 约数分钟级，属于预期偏重流程。

## AVP 测试中的依赖注入（DI）约定
visionOS 侧逐步从“在 ViewModel 内部创建依赖”迁移到“由 composition root / factory 显式注入依赖”。对应到测试侧，推荐：

| 场景 | 推荐做法 | 目的 |
| --- | --- | --- |
| 需要验证窗口切换编排 | 直接构建 `WindowCoordinator(flowState:pianoModeRegistry:)`，验证 `beginTransition/consumePendingTransition/resetToPreparation` 的纯逻辑 | 不依赖 UI 生命周期，避免引入 tracking/networking |
| 需要验证 session 注入 | 显式构建 `PianoModeRegistryService` + `PracticeSessionViewModelFactoryService`，并提供 `makeFallbackPracticeSessionViewModel` | 让“mode -> session”链路可控、可单测 |
| 需要隔离音频/回放 | 注入 fake/noop `PracticeAudioRecognitionServiceProtocol` / `PracticeSequencerPlaybackServiceProtocol` | 避免 simulator 音频/时序不稳定影响断言 |
| 需要验证 ARGuideViewModel 联动 | 用测试侧 convenience init 或自定义 `PracticeSessionViewModelFactoryProtocol`（例如返回固定 session） | 把 focus 放在 flowState/appState 的数据传递 |

最小模式（示意）：
```swift
let registry = PianoModeRegistryService(modes: [
  BluetoothMIDIPianoMode(makePracticeSessionViewModel: { dummySession }),
])
let factory = PracticeSessionViewModelFactoryService(
  pianoModeRegistry: registry,
  makeFallbackPracticeSessionViewModel: { fallbackSession }
)
let guide = ARGuideViewModel(appState: AppState(), flowState: FlowState(), pianoModeRegistry: registry, practiceSessionViewModelFactory: factory)
```

## 现状
- 当前仓库未提交 `.github/workflows/`，所有测试需要手动在本地运行。
- macOS tests 使用本地 macOS 运行 `xcodebuild test -scheme LonelyPianist -destination 'platform=macOS'`。
- AVP tests 使用本地 visionOS simulator 运行：先 `xcodebuild -showdestinations -scheme LonelyPianistAVP` 获取 concrete device id，再跑 `xcodebuild test -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,id=<device-id>'`。
- Python tests 以本地 smoke scripts 为主。

## Coverage Gaps
- 三端端到端自动化仍缺失；当前覆盖依赖单测、本地 Xcode tests、Python smoke 和人工冒烟组合。
- Python server 的模型权重、设备选择和外部依赖没有稳定 CI 环境。
