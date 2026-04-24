# AVP Calibration

## 范围
校准页覆盖 A0/C8 捕获、世界锚点存储、恢复、重新校准和定位前置条件。

## 关键对象
| 对象 | 职责 |
| --- | --- |
| `AppModel` | 存储 calibration 和定位结果 |
| `ARGuideViewModel` | Step 1 / Step 3 编排 |
| `CalibrationPointCaptureService` | 准星稳定与锚点 ID 记录 |
| `WorldAnchorCalibrationStore` | JSON 持久化 |
| `PianoKeyGeometryService` | 根据校准生成 88 键区域 |
| `KeyboardFrame` | 从 A0/C8 推导键盘局部坐标系（用于渲染与按键检测） |

## 行为
- `saveCalibrationIfPossible()` 会拒绝不完整校准。
- 保存后会 reset capture state。
- `beginCalibrationRecapture()` 会清理临时锚点。
- `resolveRuntimeCalibrationFromTrackedAnchors()` 会检查 anchor 是否存在、是否 tracked、是否足够远。
- runtime calibration 会把 **A0/C8 解释为琴键“前沿线”**（keyboard-local `z = 0`），并基于 `DeviceAnchor` 判断琴键内部方向，从而得到 `frontEdgeToKeyCenterLocalZ`（通常是 `± keyDepth/2`）。

## 坐标系约定（KeyboardFrame）

- 原点：A0（投影到 `planeHeight`）。
- +X：从 A0 指向 C8（水平投影）。
- +Y：世界向上。
- +Z：按右手系推导（满足 `cross(x, y) == z`）。注意 +Z 未必“朝向用户”，需结合设备位姿判定哪一侧是琴键内部。

## 失败类型
| 失败 | 含义 |
| --- | --- |
| `missingStoredCalibration` | 没有持久化校准 |
| `anchorMissing` | 锚点没在当前环境恢复 |
| `anchorNotTracked` | 锚点存在但未跟踪 |
| `anchorsTooClose` | A0/C8 距离过近 |
| `devicePoseUnavailable` | 设备位姿暂不可用，无法判定前后方向 |

## 调试抓手
- `calibrationStatusMessage`
- `pendingCalibrationCaptureAnchor`
- `storedCalibration`
- `practiceLocalizationState`


## Coverage Gaps
- 校准流程的空间交互仍依赖手工验证，缺少沉浸式 UI 自动化。
