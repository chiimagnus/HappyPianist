# 模块：LonelyPianistAVP

## 边界
- 负责：Step 1 校准、Step 2 曲库、Step 3 练习、沉浸空间和手部追踪。
- 不负责：macOS MIDI 映射和 Python 推理。

## 目录地图
| 路径 | 角色 |
| --- | --- |
| `AppModel.swift` | 全局状态枢纽 |
| `ViewModels/` | 业务编排 |
| `Models/Placement/` | 平面命中与放置数据结构（ray / plane / hit） |
| `Services/Placement/` | 虚拟钢琴放置相关服务（视线平面命中、键盘姿态推导） |
| `Services/Library/` | 曲库与 seed |
| `Services/MusicXML/` | 解析和时间线 |
| `Services/Tracking/` | AR tracking |
| `Services/Calibration/` | 校准捕获 |
| `Services/VirtualPiano/` | 虚拟钢琴几何与接触检测 |
| `Views/` | Step 1/2/3 UI |
| `Views/Immersive/VirtualPianoOverlayController.swift` | 虚拟钢琴 3D 渲染 |
| `Views/Immersive/GazePlaneDiskOverlayController.swift` | 虚拟钢琴放置引导：绿色圆盘 + 3D 文案 |

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
- AVP 的手部追踪、平面检测、贴皮高亮视觉舒适度与虚拟钢琴放置体验仍需要 Vision Pro 真机验证；simulator 无法覆盖真实传感数据质量。

## 更新记录（Update Notes）
- 2026-04-26: 修复模块页内部链接；更新 AVP 验证链路描述（shared scheme 已存在且在 CI 使用）。
- 2026-05-01: Step 3 练习的 RealityKit 引导从光柱迁移为琴键贴皮高亮（decal）。
- 2026-05-02: 虚拟钢琴放置改为“视野中心平面 + 双手确认”，新增 placement 模型与服务，并增加圆盘 overlay。
