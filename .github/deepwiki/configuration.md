# 配置

## 配置入口
| 配置面 | 位置 / 界面 | 写入方 | 说明 |
| --- | --- | --- | --- |
| 对话中断策略 | macOS Dialogue 页面 | `LonelyPianistViewModel` -> `UserDefaults` | `ignore / interrupt / queue` |
| 映射规则 | macOS Mappings 页面 | ViewModel -> `SwiftDataMappingConfigRepository` | 单键/和弦与 velocity 规则 |
| 录音与回放输出 | macOS Recorder 页面 | ViewModel -> playback service | 选择 Built-in Sampler 或 MIDI 目的地 |
| AVP 校准 | Immersive HUD (`Set A0/C8`, `Save`) | `PianoCalibrationStore` | 写 `piano-calibration.json` |
| Python 推理配置 | 环境变量 | shell / 启动脚本 | 模型路径、设备、调试开关 |

## 运行时配置
| 配置项 | 位置 | 默认值 / 示例 | 影响 |
| --- | --- | --- | --- |
| Dialogue WS 地址 | `DialogueManager` | `ws://127.0.0.1:8765/ws` | 对话服务连接目标 |
| 静默阈值 | `DefaultSilenceDetectionService` | `2.0s` | phrase 切分触发时机 |
| 对话策略默认值 | `LonelyPianistApp` 注册 | `.interrupt` | 回放期间输入行为 |
| PressDetection 冷却 | `PressDetectionService` | `0.15s` | 避免同键抖动重复触发 |
| Chord 累积窗口 | `ChordAttemptAccumulator` | `0.6s` | 跨多次按下识别同一步和弦 |
| 练习容差 | `PracticeSessionViewModel.noteMatchTolerance` | `1` | 允许 ±1 半音容错 |

## 构建与发布配置
| 配置项 | 位置 | 作用 | 联动项 |
| --- | --- | --- | --- |
| 主工程与 targets | `LonelyPianist.xcodeproj/project.pbxproj` | 定义 app/test 目标 | scheme 与 test 命令 |
| macOS 共享 scheme | `xcshareddata/xcschemes/LonelyPianist.xcscheme` | build/test/run 参数 | 本地/自动化命令 |
| RealityKitContent 平台声明 | `Packages/RealityKitContent/Package.swift` | 最低平台约束 | AVP 相关编译能力 |
| xcodebuildmcp 默认 profile | `.xcodebuildmcp/config.yaml` | 常用 scheme/simulator 设置 | 本地调试流程 |

## 权限、认证与敏感信息
- macOS：
  - `AccessibilityPermissionService` 请求系统辅助功能权限；
  - app entitlements 启用 sandbox、网络客户端与用户选择文件只读。
- visionOS：
  - `Info.plist` 声明 `NSHandsTrackingUsageDescription`、`NSWorldSensingUsageDescription`。
- Python：
  - 默认本地回环地址，不涉及远端鉴权；
  - 模型路径与设备通过环境变量控制，不应把模型权重提交仓库。

## 功能开关与行为差异
- `DialoguePlaybackInterruptionBehavior`：影响回放时输入处理（忽略/打断/排队）。
- `DIALOGUE_DEBUG=1`：启用服务端调试包落盘（请求、响应、MIDI、摘要）。
- `AMT_MODEL_DIR / AMT_MODEL_ID / AMT_DEVICE`：控制模型加载来源与硬件执行路径。

## 配置漂移检查
- 修改对话协议字段时需同步：
  - macOS `DialogueNote` / `DialogueGenerateParams`
  - Python `server/protocol.py`
  - WebSocket 客户端编解码逻辑
- 修改持久化模型时需同步 SwiftData schema（`ModelContainerFactory`）与 repository 映射。
- 修改 AVP 校准结构时需考虑历史 `piano-calibration.json` 兼容性。

## 常见误配
- **未授权 Accessibility**：Start Listening 后无法正常执行按键注入。
- **未启动 Python 服务**：Dialogue 进入失败或生成报错。
- **模型目录缺权重**：`inference.py` 抛出 “weights not found”。
- **AVP 未完成校准**：有 step 但不进入有效键位高亮。

## 示例片段
```swift
UserDefaults.standard.register(defaults: [
    DialoguePlaybackInterruptionBehavior.userDefaultsKey:
    DialoguePlaybackInterruptionBehavior.interrupt.rawValue
])
```

```bash
export AMT_MODEL_DIR=/path/to/music-large-800k
export AMT_DEVICE=mps
export DIALOGUE_DEBUG=1
python -m uvicorn server.main:app --host 127.0.0.1 --port 8765
```

## Coverage Gaps
- 仓库未提供集中化 `.env.example`；Python 配置项仍分散在 README 与代码。
- AVP scheme 共享配置在仓库中未见同名 xcscheme 文件，命令需按本地可见 scheme 为准。

## 来源引用（Source References）
- `LonelyPianist/LonelyPianistApp.swift`
- `LonelyPianist/Models/Dialogue/DialoguePlaybackInterruptionBehavior.swift`
- `LonelyPianist/Services/Dialogue/DialogueManager.swift`
- `LonelyPianist/Services/Dialogue/DefaultSilenceDetectionService.swift`
- `LonelyPianist/LonelyPianist.entitlements`
- `LonelyPianistAVP/Info.plist`
- `LonelyPianistAVP/Services/PianoCalibrationStore.swift`
- `LonelyPianistAVP/Services/HandTracking/PressDetectionService.swift`
- `piano_dialogue_server/README.md`
- `piano_dialogue_server/server/inference.py`
- `piano_dialogue_server/server/debug_artifacts.py`
- `piano_dialogue_server/omr/cli.py`
- `piano_dialogue_server/omr/packaging/build_pyinstaller.sh`
- `.xcodebuildmcp/config.yaml`
