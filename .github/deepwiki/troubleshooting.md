# 故障排查

## 症状索引
| 症状 | 可能范围 | 首查位置 | 快速判断 |
| --- | --- | --- | --- |
| Start Listening 后无动作 | macOS 权限 / MIDI 输入 | Runtime 状态区、Accessibility | `hasAccessibilityPermission` 是否为 true |
| Dialogue 无回应或报连接失败 | Python 服务未启动 / WS 异常 | `DialogueControlView` + 服务日志 | `curl /health` 是否返回 `{"status":"ok"}` |
| AVP 无高亮或偏移严重 | 校准 / 手部追踪状态 | Immersive HUD + calibration 状态 | 是否已保存 A0/C8，Hands 状态是否 running |
| 回放无声或无 MIDI 输出 | 输出路由选择错误 | Recorder output 选择 + 目的地列表 | 选中 Built-in Sampler 或有效 MIDI destination |

## 第一现场信息
- macOS：
  - Runtime `statusMessage`、`connectionDescription`、`recentLogs`。
  - Sources 列表是否为空，Pressed 是否随键盘变化。
- Python：
  - `/health`、uvicorn 控制台日志。
  - 开启 `DIALOGUE_DEBUG=1` 后检查 `out/dialogue_debug/requests/<id>/summary.json`。

## 常见故障场景
### 场景 1：映射规则已配置但目标应用无按键输入
- 现象：Runtime 看到 MIDI 事件，但目标应用未收到快捷键。
- 可能原因：Accessibility 未授权、应用失焦、仅按下修饰键被忽略。
- 排查步骤：
  1. 查看 `hasAccessibilityPermission` 与状态文本。
  2. 点击 `Grant Permission` 并确认系统设置内已勾选。
  3. 用最简单单键规则（如 C4 -> K）重测。
- 处理方式：重新授权后重启监听；必要时重启 App 触发系统权限刷新。

### 场景 2：Dialogue 一直停在 listening 或 thinking
- 现象：Start Dialogue 后无回复音符。
- 可能原因：后端未运行、模型加载失败、静默未达触发条件。
- 排查步骤：
  1. `curl -s http://127.0.0.1:8765/health`。
  2. 服务端查看是否收到 `generate` 请求。
  3. 检查踏板是否一直按下（会阻止静默触发）。
- 处理方式：启动/修复服务、确认模型权重目录、释放踏板并等待静默窗。

### 场景 4：AVP 看到手指点但步骤不推进
- 现象：手指绿色点正常，当前 step 不变。
- 可能原因：校准偏移、容差不足、和弦未在时间窗内完成。
- 排查步骤：
  1. 重做 A0/C8 并保存。
  2. 检查当前 step 目标音与实际按键差距。
  3. 观察是否在累积窗口（默认 0.6s）内完成和弦。
- 处理方式：重校准、调整演奏速度与准确度，必要时临时 `Mark Correct` 校验流程。

## 调试入口与命令
| 入口 / 命令 | 位置 | 用途 | 备注 |
| --- | --- | --- | --- |
| `xcodebuild test ... -scheme LonelyPianist` | 仓库根 | 验证 macOS 逻辑回归 | 覆盖映射/录音/静默检测 |
| `xcodebuild test ... -scheme LonelyPianistAVP` | 仓库根 | 验证 AVP 算法层 | 依赖 visionOS simulator |
| `curl -s http://127.0.0.1:8765/health` | 任意 | 服务在线检测 | 返回 `status: ok` |
| `../.venv/bin/python test_client.py` | `server/` | Dialogue 端到端验证 | 生成 `out/server_reply.mid` |
| `python -m omr.cli --input ...` | `piano_dialogue_server/` | 独立 OMR 转换 | 输出 `job_dir` 与 `musicxml_path` |

## 恢复与回退
- 对话链路恢复：先停掉 Dialogue，再重启 Python 服务与 Dialogue。
- 校准恢复：删除或覆盖 `piano-calibration.json` 后重新 A0/C8 标定。
- 回放恢复：切回 Built-in Sampler 以排除外部 MIDI 目的地问题。

## 已知尖锐边界
- OMR 多页处理能力尚未实现 merge-pages。
- AVP 引导对空间校准依赖极强，轻微偏差会放大到键位漂移。
- Dialogue 依赖本地模型与显存/内存，首次加载时间较长且可能失败。

## 示例片段
```swift
guard hasAccessibilityPermission else {
    statusMessage = "Accessibility permission is required"
    return
}
```

## Coverage Gaps
- 尚未沉淀统一日志采集策略（目前依赖控制台 + 本地文件）。
- 未见自动化“故障注入”脚本用于系统级恢复演练。

## 来源引用（Source References）
- `LonelyPianist/ViewModels/LonelyPianistViewModel.swift`
- `LonelyPianist/Views/Runtime/StatusSectionView.swift`
- `LonelyPianist/Services/System/AccessibilityPermissionService.swift`
- `LonelyPianist/Services/Dialogue/DialogueManager.swift`
- `LonelyPianistAVP/ImmersiveView.swift`
- `LonelyPianistAVP/Services/Calibration/CalibrationPointCaptureService.swift`
- `piano_dialogue_server/README.md`
- `piano_dialogue_server/server/main.py`
- `piano_dialogue_server/server/debug_artifacts.py`
