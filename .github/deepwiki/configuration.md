# 配置

## 配置入口总览
| 配置面 | 位置 / 界面 | 写入方 | 说明 |
| --- | --- | --- | --- |
| 对话打断策略 | macOS Dialogue 页 | `UserDefaults` | `ignore / interrupt / queue` |
| 映射规则 | macOS Mappings 页 | SwiftData repository | 单键/和弦/velocity 规则 |
| AVP 世界锚点校准 | Step 1 页面 | `WorldAnchorCalibrationStore` | 保存 A0/C8 anchor ID |
| AVP 曲库索引 | Step 2 页面 | `SongLibraryIndexStore` | 维护曲目元数据 |
| Python 推理参数 | shell 环境变量 | `inference.py` | 模型目录、设备、调试开关 |

## 运行时关键参数
| 配置项 | 位置 | 默认值 / 常量 | 影响 |
| --- | --- | --- | --- |
| Dialogue WS 地址 | `DialogueManager` | `ws://127.0.0.1:8765/ws` | 对话连接目标 |
| 静默阈值 | `DefaultSilenceDetectionService` | `2.0s` | phrase 切分触发 |
| AVP provider 启动超时 | `ARGuideViewModel` | `5s` | world/hand provider 等待窗口 |
| AVP 定位超时 | `ARGuideViewModel` | `5s` | Step 3 定位失败阈值 |
| PressDetection 冷却 | `PressDetectionService` | `0.15s` | 避免重复触发 |
| Chord 累积窗口 | `ChordAttemptAccumulator` | `0.6s` | 多指和弦识别容差 |
| 练习匹配容差 | `PracticeSessionViewModel` | `±1 半音` | 键位匹配宽容度 |

## 构建与工程配置
| 配置项 | 位置 | 作用 | 备注 |
| --- | --- | --- | --- |
| 主工程 targets | `LonelyPianist.xcodeproj/project.pbxproj` | 定义 macOS / AVP / Tests | 可见 `LonelyPianistAVP` 与 `LonelyPianistAVPTests` |
| 共享 scheme | `xcshareddata/xcschemes/LonelyPianist.xcscheme` | 可复用构建入口 | 当前仅见 macOS 共享 scheme |
| xcodebuildmcp profile | `.xcodebuildmcp/config.yaml` | 提供 `avp` profile | 可用于本地 AVP 运行流程 |
| RealityKitContent 平台约束 | `Packages/RealityKitContent/Package.swift` | 声明 `.visionOS(.v26)` 等 | 影响包编译目标 |

## 权限、认证与敏感信息
- macOS `LonelyPianist.entitlements`：
  - sandbox、network client、user-selected files read-only。
- AVP `Info.plist`：
  - 声明 `NSHandsTrackingUsageDescription`；
  - 声明 `com.recordare.musicxml` 导入类型。
- Python：
  - 服务默认本地回环地址；
  - 模型权重不应提交到仓库。

## 功能开关与环境变量
| 变量 | 默认 / 行为 | 说明 |
| --- | --- | --- |
| `AMT_MODEL_DIR` | 无默认 | 优先使用本地模型目录 |
| `AMT_MODEL_ID` | `stanford-crfm/music-large-800k` | 无本地目录时使用 |
| `AMT_DEVICE` | 自动（mps/cuda/cpu） | 覆盖推理设备 |
| `DIALOGUE_DEBUG` | 关闭 | 开启后写 `out/dialogue_debug/` |
| `HF_ENDPOINT` | 代码中默认 `https://hf-mirror.com` | HuggingFace 镜像地址 |

## 配置漂移检查清单
- 修改对话协议字段时，需同步：
  - `LonelyPianist/Models/Dialogue/*`
  - `LonelyPianist/Services/Dialogue/*`
  - `piano_dialogue_server/server/protocol.py`
- 修改 AVP 曲库结构时，需同步：
  - `SongLibraryIndex` 模型
  - `SongLibraryIndexStore` 编解码
  - `SongLibrarySeeder` 迁移逻辑
- 修改校准格式时，需同步：
  - `StoredWorldAnchorCalibration`
  - `WorldAnchorCalibrationStore`
  - `ARGuideViewModel` 定位流程

## 常见误配
- 未授权 Accessibility：映射执行无效。
- 未启动 Python 服务或模型目录为空：Dialogue 失败。
- AVP 仅有 stored calibration 但 world anchor 未追踪：Step 3 定位失败。
- 曲库条目存在但目标文件被外部删除：preparePractice 失败。

## Coverage Gaps
- 仓库未提供 `.env.example`，Python 环境变量仍分散在 README 与代码中。
- `LonelyPianistAVP` 共享 scheme 仍未入库，自动化命令一致性不足。

## 来源引用（Source References）
- `LonelyPianist/LonelyPianistApp.swift`
- `LonelyPianist/Models/Dialogue/DialoguePlaybackInterruptionBehavior.swift`
- `LonelyPianist/Services/Dialogue/DialogueManager.swift`
- `LonelyPianist/Services/Dialogue/DefaultSilenceDetectionService.swift`
- `LonelyPianist/LonelyPianist.entitlements`
- `LonelyPianistAVP/Info.plist`
- `LonelyPianistAVP/ViewModels/ARGuideViewModel.swift`
- `LonelyPianistAVP/Services/WorldAnchorCalibrationStore.swift`
- `LonelyPianistAVP/Services/Library/SongLibraryIndexStore.swift`
- `piano_dialogue_server/server/inference.py`
- `.xcodebuildmcp/config.yaml`
