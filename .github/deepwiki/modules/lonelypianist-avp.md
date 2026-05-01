# 模块：LonelyPianistAVP

## 边界
- 负责：Step 1 校准、Step 2 曲库、Step 3 练习、沉浸空间和手部追踪。
- 不负责：macOS MIDI 映射和 Python 推理。

## 目录地图
| 路径 | 角色 |
| --- | --- |
| `AppModel.swift` | 全局状态枢纽 |
| `ViewModels/` | 业务编排 |
| `ViewModels/VirtualPianoPlacementViewModel.swift` | 虚拟钢琴放置状态机 |
| `Services/Library/` | 曲库与 seed |
| `Services/MusicXML/` | 解析和时间线 |
| `Services/Tracking/` | AR tracking |
| `Services/Calibration/` | 校准捕获 |
| `Services/VirtualPiano/` | 虚拟钢琴几何与接触检测 |
| `Views/` | Step 1/2/3 UI |
| `Views/Immersive/VirtualPianoOverlayController.swift` | 虚拟钢琴 3D 渲染 |

## 入口与生命周期
| 入口 | 行为 |
| --- | --- |
| `LonelyPianistAVPApp.swift` | 加载校准、seed 曲库 |
| `ContentView` | Step 1/2/3 路由 |
| `ARGuideViewModel.enterPracticeStep()` | 开启练习定位（虚拟钢琴模式跳过实体定位） |
| `ARGuideViewModel.setPracticeVirtualPianoEnabled()` | 切换虚拟钢琴模式 |
| `SongLibraryViewModel.preparePractice()` | 解析谱面并注入 steps |

## 重要子页
- [Library](lonelypianist-avp-library.md)
- [Calibration](lonelypianist-avp-calibration.md)
- [MusicXML](lonelypianist-avp-musicxml.md)
- [Tracking](lonelypianist-avp-tracking.md)
- [Practice](lonelypianist-avp-practice.md)

## 风险点
- `resolveRuntimeCalibrationFromTrackedAnchors`
- `runPracticeLocalization`
- `importMusicXML`
- `startAutoplayTaskIfNeeded`


## Coverage Gaps
- AVP simulator tests 已可在 GitHub Actions 上跑通，但仍不能替代 Vision Pro 真机对手部追踪与贴皮高亮视觉舒适度的验证。

## 更新记录（Update Notes）
- 2026-04-26: 修复模块页内部链接；更新 AVP 验证链路描述（shared scheme 已存在且在 CI 使用）。
- 2026-05-01: Step 3 练习的 RealityKit 引导从光柱迁移为琴键贴皮高亮（decal）。
