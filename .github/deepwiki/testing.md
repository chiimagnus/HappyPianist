# 测试

## 测试策略
| 维度 | 方法 | 目标 |
| --- | --- | --- |
| macOS 逻辑 | Swift Testing | mapping / recorder / dialogue |
| AVP 逻辑 | Swift Testing | MusicXML / calibration / practice / library |
| Python 自检 | 脚本 + WS client | 模型生成与协议回环 |

## 命令
| 命令 | 适用场景 |
| --- | --- |
| `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianist -destination 'platform=macOS'` | macOS 回归 |
| `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,name=Apple Vision Pro'` | AVP 回归 |
| `cd piano_dialogue_server && python scripts/test_generate.py` | 离线推理 sanity check |
| `cd piano_dialogue_server/server && ../.venv/bin/python test_client.py` | WS 回环 |
| `curl -s http://127.0.0.1:8765/health` | 服务健康检查 |

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
| 风险区 | 为什么要测 |
| --- | --- |
| 速度阈值和和弦严格相等 | 直接影响映射触发 |
| 录音开闭音 | 影响 take 完整性 |
| Dialogue 状态机 | 影响 turn-based 体验 |
| 曲库索引 / 文件一致性 | 影响 Step 2 / Step 3 |
| 校准和定位失败分支 | 影响沉浸式流程 |
| MusicXML expressivity | 影响练习步骤和 autoplay |

## 手工冒烟
1. macOS 授权 Accessibility，验证 Start Listening、Mapping、Recorder、Dialogue。
2. Python 先跑 `/health`，再跑 `test_client.py`。
3. AVP 导入 MusicXML，完成校准，进入练习并验证高亮 / 跳步 / 自动播放。

## 现状
- 没有 `.github/workflows/*`，所以测试门禁不在 CI 上自动定义。

## Coverage Gaps
- 三端端到端自动化仍缺失；当前覆盖依赖单测和人工冒烟组合。
