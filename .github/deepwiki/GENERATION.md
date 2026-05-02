# Generation Metadata

## Run info
| Item | Value |
| --- | --- |
| Commit hash | 90ffdde8c0f4d7eb3c6c85cea09f442eafb64556 |
| Branch name | okcrh1 |
| Generated at | 2026-05-02T10:03:14+08:00 |
| Output language | Chinese |
| Generation mode | Incremental update via `deepwiki` skill |

## Key updates in this generation
| Area | Update |
| --- | --- |
| 虚拟钢琴放置 | Step 3 虚拟钢琴放置改为“视野中心平面 + 绿色圆盘 + 双手掌心稳定确认（3s/3cm）”，并通过 `WorldAnchor` 在 Step 3 内复用放置。 |
| Tracking / 权限 | `ARTrackingService` 新增 `PlaneDetectionProvider`（horizontal planes），并在 hand skeleton 中近似计算 `*-palmCenter`；AVP 需要 `NSWorldSensingUsageDescription`。 |
| 文档一致性 | 修正 deepwiki 对 `.github/workflows/` 的假设：当前仓库不包含 GitHub Actions workflows，测试与格式化均为本地手动运行。 |

## Current Coverage Gaps
- The repo currently has no GitHub Actions workflows; all tests are manual/local.
- There is no unified release workflow.
- There is no full macOS -> Python -> AVP end-to-end automated test.
- Audio recognition fallback behavior and performance tuning still requires real-device verification.
- Audio recognition engine failures (e.g., RemoteIO -10851) are still environment-dependent; simulator behavior is not a reliable proxy for Vision Pro devices.
- AutoplayPerformanceTimeline complex edge cases (e.g., simultaneous pedal up/down) may need more test coverage.
- Virtual piano placement experience (plane detection stability, palm confirmation thresholds) and 3D rendering (key size, spacing, material) need Vision Pro real-device verification.
- KeyContactDetectionService hysteresis thresholds (press 2mm / release 8mm) need real-device tuning.
- Decal highlight alignment, z-fighting, and visual comfort need Vision Pro real-device verification.
