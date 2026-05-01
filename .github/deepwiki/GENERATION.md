# Generation Metadata

## Run info
| Item | Value |
| --- | --- |
| Commit hash | b3aace5e35769ca54b8d942ae1e9f7d1b485967b |
| Branch name | crh |
| Generated at | 2026-05-01T22:11:31+08:00 |
| Output language | Chinese |
| Generation mode | Incremental update via `deepwiki` skill |

## Key updates in this generation
| Area | Update |
| --- | --- |
| AR 引导 | Step 3 的 RealityKit 引导从光柱迁移为琴键贴皮高亮（decal），贴图资源为 `KeyDecalSoftRect`。 |
| 练习模块 | 移除 correct/wrong feedback state 描述，匹配成功直接推进下一步（错误输入无视觉反馈）。 |
| 数据流与排障 | 更新空间提示数据流与排障入口，改为贴皮高亮（不再依赖 `KeyBeamFourSideAtlas`）。 |

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
- Decal highlight alignment, z-fighting, and visual comfort need Vision Pro real-device verification.
