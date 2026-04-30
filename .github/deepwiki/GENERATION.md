# Generation Metadata

## Run info
| Item | Value |
| --- | --- |
| Commit hash | 4c7b18c6576a75f4dd7d11144a3cf0f2998d42eb |
| Branch name | crh |
| Generated at | 2026-04-30T12:00:00+08:00 |
| Output language | Chinese |
| Generation mode | Incremental update via `deepwiki` skill |

## Key updates in this generation
| Area | Update |
| --- | --- |
| 虚拟钢琴模式 | 新增完整的虚拟钢琴功能文档：放置状态机、88 键几何生成、迟滞按键检测、live note on/off 实时发声、3D 键盘渲染、安全清音机制。 |
| 练习模块 | 更新 practice 模块页的范围、关键对象表、测试覆盖和调试抓手，新增虚拟钢琴专属章节。 |
| 架构 | 在组件边界表和依赖图中新增 VirtualPianoPlacementViewModel、VirtualPianoKeyGeometryService、KeyContactDetectionService、VirtualPianoOverlayController。 |
| 数据流 | 新增虚拟钢琴数据流（放置、键盘生成、渲染、按键检测、实时发声）和故障恢复条目。 |
| 术语表 | 新增虚拟钢琴相关术语和易混淆概念说明。 |

## Current Coverage Gaps
- Python smoke tests are not yet part of GitHub Actions.
- There is no unified release workflow.
- There is no full macOS -> Python -> AVP end-to-end automated test.
- PR Tests workflow has been deleted; all tests must be run manually.
- Audio recognition fallback behavior and performance tuning still requires real-device verification.
- Audio recognition engine failures (e.g., RemoteIO -10851) are still environment-dependent; simulator behavior is not a reliable proxy for Vision Pro devices.
- AutoplayPerformanceTimeline complex edge cases (e.g., simultaneous pedal up/down) may need more test coverage.
- Virtual piano 3D rendering (key size, spacing, material) and interaction (ManipulationComponent drag/scale) need Vision Pro real-device verification.
- KeyContactDetectionService hysteresis thresholds (press 2mm / release 8mm) need real-device tuning.
