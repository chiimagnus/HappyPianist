# 模块：LonelyPianistAVP

## 边界
- 负责：Step 1 校准、Step 2 曲库、Step 3 练习、沉浸空间和手部追踪。
- 不负责：macOS MIDI 映射和 Python 推理。

## 目录地图
| 路径 | 角色 |
| --- | --- |
| `AppModel.swift` | 全局状态枢纽 |
| `ViewModels/` | 业务编排 |
| `Services/Library/` | 曲库与 seed |
| `Services/MusicXML/` | 解析和时间线 |
| `Services/Tracking/` | AR tracking |
| `Services/Calibration/` | 校准捕获 |
| `Views/` | Step 1/2/3 UI |

## 入口与生命周期
| 入口 | 行为 |
| --- | --- |
| `LonelyPianistAVPApp.swift` | 加载校准、seed 曲库 |
| `ContentView` | Step 1/2/3 路由 |
| `ARGuideViewModel.enterPracticeStep()` | 开启练习定位 |
| `SongLibraryViewModel.preparePractice()` | 解析谱面并注入 steps |

## 重要子页
- [Library](modules/lonelypianist-avp-library.md)
- [Calibration](modules/lonelypianist-avp-calibration.md)
- [MusicXML](modules/lonelypianist-avp-musicxml.md)
- [Tracking](modules/lonelypianist-avp-tracking.md)
- [Practice](modules/lonelypianist-avp-practice.md)

## 风险点
- `resolveRuntimeCalibrationFromTrackedAnchors`
- `runPracticeLocalization`
- `importMusicXML`
- `startAutoplayTaskIfNeeded`


## Coverage Gaps
- Shared scheme 缺失仍是 AVP 验证链路的主要不稳定来源。

