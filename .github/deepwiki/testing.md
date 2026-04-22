# 测试

## 测试策略
| 维度 | 方法 | 自动化程度 | 目标 |
| --- | --- | --- | --- |
| 业务逻辑 | Swift Testing 单元测试 | 高 | 稳定状态机、解析与核心算法 |
| 服务契约 | Python 协议与生成脚本 | 中 | 防止 WS 字段漂移 |
| 文件/存储一致性 | AVP 曲库与校准 store 测试 | 高 | 防止索引-文件不一致 |
| 手工冒烟 | 跨运行面链路验证 | 中 | 覆盖权限、设备、沉浸空间等真实条件 |

## 测试层次与覆盖面
| 层次 | 位置 | 覆盖对象 | 备注 |
| --- | --- | --- | --- |
| macOS 单测 | `LonelyPianistTests/` | Mapping、Recording、Silence、ViewModel 状态 | 使用 `import Testing` |
| AVP 单测 | `LonelyPianistAVPTests/` | MusicXML/Step、Localization 策略、SongLibrary 文件与索引、AudioPlayer 状态 | 使用 `import Testing` |
| Python 自检 | `piano_dialogue_server/scripts/`、`server/test_client.py` | 模型生成与 WS 回环 | 依赖本地模型环境 |

## 执行命令与顺序
| 命令 | 用途 | 何时执行 |
| --- | --- | --- |
| `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianist -destination 'platform=macOS'` | macOS 单测 | 改动 `LonelyPianist/` 后 |
| `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,name=Apple Vision Pro'` | AVP 单测 | 改动 `LonelyPianistAVP/` 后 |
| `xcodebuildmcp simulator build-and-run --profile avp` | AVP 本地运行验证 | 共享 scheme 不可见时的替代路径 |
| `curl -s http://127.0.0.1:8765/health` | 服务健康检查 | 启动 Python 服务后 |
| `cd piano_dialogue_server/server && ../.venv/bin/python test_client.py` | WS 端到端回环 | 改动协议/推理后 |
| `cd piano_dialogue_server && python scripts/test_generate.py` | 离线生成 sanity check | 改动 `inference.py` 后 |

## 关键回归区域
- `DialogueManager` 状态流与中断策略。
- `DefaultMappingEngine` 的和弦严格匹配语义。
- `ARGuideViewModel` 的定位状态机（provider/anchor 超时与失败分支）。
- `SongLibraryViewModel` 的导入、删除、绑定音频一致性路径。

## AVP 新增/关键测试样本
| 测试文件 | 核心验证 |
| --- | --- |
| `PracticeLocalizationPolicyTests.swift` | Step 3 入口阻断与定位失败策略 |
| `WorldAnchorCalibrationStoreTests.swift` | 校准文件读写 |
| `SongLibraryIndexStoreTests.swift` | 索引空值/损坏/写回行为 |
| `SongFileStoreTests.swift` | 导入文件命名与删除行为 |
| `AudioImportServiceTests.swift` | 音频导入与去重 |
| `SongAudioPlayerStateTests.swift` | 播放状态切换与完成回调 |
| `SongLibrarySeederLegacyCleanupTests.swift` | 旧目录迁移清理 |

## 手工冒烟建议
1. macOS：授权 Accessibility，验证映射与录制回放。
2. Python：启动服务并跑 `/health` + `test_client.py`。
3. AVP：Step 1 完成校准，Step 2 选曲，Step 3 定位成功后推进步骤。
4. AVP 曲库：导入 MusicXML、绑定音频、删除曲目，确认索引与文件一致。

## CI / 质量门禁现状
- 目前仓库未包含 `.github/workflows/*`。
- 现阶段质量门槛依赖“本地单测 + 服务脚本 + 手工冒烟”组合。

## Coverage Gaps
- 尚未建立“提交即跑”的统一门禁流水线。
- 三端联动 E2E 自动化仍为空白区域。

## 来源引用（Source References）
- `AGENTS.md`
- `LonelyPianistTests/Mapping/UnifiedMappingConfigTests.swift`
- `LonelyPianistTests/Recording/DefaultRecordingServiceTests.swift`
- `LonelyPianistTests/SilenceDetectionServiceTests.swift`
- `LonelyPianistAVPTests/PracticeLocalizationPolicyTests.swift`
- `LonelyPianistAVPTests/WorldAnchorCalibrationStoreTests.swift`
- `LonelyPianistAVPTests/SongLibraryIndexStoreTests.swift`
- `LonelyPianistAVPTests/SongFileStoreTests.swift`
- `LonelyPianistAVPTests/AudioImportServiceTests.swift`
- `LonelyPianistAVPTests/SongAudioPlayerStateTests.swift`
- `piano_dialogue_server/server/test_client.py`
- `piano_dialogue_server/scripts/test_generate.py`
