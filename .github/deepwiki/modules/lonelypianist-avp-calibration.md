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

## 行为
- `saveCalibrationIfPossible()` 会拒绝不完整校准。
- 保存后会 reset capture state。
- `beginCalibrationRecapture()` 会清理临时锚点。
- `resolveRuntimeCalibrationFromTrackedAnchors()` 会检查 anchor 是否存在、是否 tracked、是否足够远。

## 失败类型
| 失败 | 含义 |
| --- | --- |
| `missingStoredCalibration` | 没有持久化校准 |
| `anchorMissing` | 锚点没在当前环境恢复 |
| `anchorNotTracked` | 锚点存在但未跟踪 |
| `anchorsTooClose` | A0/C8 距离过近 |

## 调试抓手
- `calibrationStatusMessage`
- `pendingCalibrationCaptureAnchor`
- `storedCalibration`
- `practiceLocalizationState`


## Coverage Gaps
- 校准流程的空间交互仍依赖手工验证，缺少沉浸式 UI 自动化。

