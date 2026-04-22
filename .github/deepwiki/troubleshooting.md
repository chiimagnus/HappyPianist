# 故障排查

## 症状索引
| 症状 | 可能范围 | 首查位置 | 快速判断 |
| --- | --- | --- | --- |
| Start Listening 后目标应用无响应 | macOS 权限 / MIDI 输入 | Runtime 状态区、Accessibility | `hasAccessibilityPermission` 是否为 true |
| Dialogue 无回应 | Python 服务 / 模型加载 | `/health`、服务日志 | `curl /health` 是否为 `ok` |
| Step 3 定位失败 | AVP provider / world anchors | `practiceLocalizationStatusText` | 是否已存在 stored calibration + provider running |
| 曲库条目可见但无法开始练习 | AVP 文件/索引不一致 | SongLibraryView 提示 | 目标 MusicXML 文件是否存在 |
| 音频“聆听”失败 | 音频文件丢失或格式不支持 | SongLibrary 错误弹窗 | 条目 `audioFileName` 指向的文件是否存在 |

## 第一现场信息
- macOS：`statusMessage`、`recentLogs`、Sources 与 Pressed 状态。
- AVP：
  - `practiceLocalizationStatusText`、`calibrationStatusMessage`；
  - provider state（hand/world）；
  - HUD 中进度与反馈状态。
- Python：`uvicorn` 日志、`/health`、`out/dialogue_debug/*`。

## 常见故障场景
### 场景 1：映射规则已配置但无快捷键输出
1. 检查系统设置中 Accessibility 授权。
2. 使用最小规则（单键）复现。
3. 确认目标应用处于可接收焦点状态。

### 场景 2：Dialogue 长时间无回复
1. `curl -s http://127.0.0.1:8765/health`。
2. 检查 `AMT_MODEL_DIR` 是否有权重文件。
3. 检查踏板是否持续按下导致静默不触发。

### 场景 3：AVP Step 3 反复定位失败
1. 确认 Step 1 已保存校准（非仅捕获未保存）。
2. 观察失败类型：`anchorMissing` / `anchorNotTracked` / `providerNotRunning`。
3. 返回 Step 1 执行“重新校准”，再进入 Step 3。

### 场景 4：曲库删除后报文件删除失败
1. 这是“索引已删、文件删除失败”的已知分支。
2. 手工检查 `Documents/SongLibrary/scores|audio` 是否残留文件。
3. 必要时手工清理残留文件，保持索引与文件一致。

## 调试命令
| 命令 | 用途 |
| --- | --- |
| `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianist -destination 'platform=macOS'` | macOS 回归 |
| `xcodebuild test -project LonelyPianist.xcodeproj -scheme LonelyPianistAVP -destination 'platform=visionOS Simulator,name=Apple Vision Pro'` | AVP 回归 |
| `curl -s http://127.0.0.1:8765/health` | 服务健康检查 |
| `cd piano_dialogue_server/server && ../.venv/bin/python test_client.py` | WS 回环验证 |

## 恢复与回退建议
- Dialogue：停止对话 -> 重启 Python 服务 -> 重新 Start Dialogue。
- AVP 校准：Step 1 重新校准并保存，避免直接在 Step 3 反复重试。
- 曲库异常：先删除异常条目再重新导入，必要时清理残留文件。

## 已知尖锐边界
- AVP 定位依赖 world anchor 在当前空间可追踪，场景变化会导致恢复失败。
- 本地模型首次加载耗时长，低内存设备容易触发生成失败或延迟显著增加。

## Coverage Gaps
- 尚未形成统一日志采集与聚合方案（目前以控制台与本地文件为主）。

## 来源引用（Source References）
- `LonelyPianist/ViewModels/LonelyPianistViewModel.swift`
- `LonelyPianist/Services/System/AccessibilityPermissionService.swift`
- `LonelyPianist/Services/Dialogue/DialogueManager.swift`
- `LonelyPianistAVP/ViewModels/ARGuideViewModel.swift`
- `LonelyPianistAVP/ViewModels/Library/SongLibraryViewModel.swift`
- `LonelyPianistAVP/Services/Tracking/ARTrackingService.swift`
- `LonelyPianistAVP/Services/Library/SongFileStore.swift`
- `piano_dialogue_server/server/main.py`
- `piano_dialogue_server/server/debug_artifacts.py`
