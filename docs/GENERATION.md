# Generation Metadata

## Run info
| Item | Value |
| --- | --- |
| Commit hash | 61a1000 |
| Branch name | crh1 |
| Generated at | 2026-05-18T12:25:34+08:00 |
| Output language | Chinese |
| Generation mode | Incremental update via `neat-freak` (docs-as-canonical) |

## Key updates in this generation
| Area | Update |
| --- | --- |
| INDEX 去重 | `docs/INDEX.md` 收敛为“导航入口”，移除命令/自动化事实/coverage 叙述，避免与 `workflow.md` 重复。 |
| Overview 去重 | `docs/overview.md` 移除构建命令与持久化表格，分别收敛到 `workflow.md` 与 `storage.md`。 |
| Architecture 去重 | `docs/architecture.md` 用“按模块入口”替代组件长表，并移除重复的 CI/Actions 段落。 |
| Testing 移除 | 删除 `docs/testing.md`，把“本地验证命令”收敛进 `docs/workflow.md`。 |

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
- AVP Bonjour 发现与 `/generate` 请求强依赖同一局域网与 Local Network 授权；denied/解析失败仍需真机验证与网络环境排查。
- 单谱表自动分手是工程启发式：对交错声部/极端音域分配的曲谱，可能与人类分手不一致；目前不提供 per-score override。
- 双 part 归一化仅处理恰好 2 个 part 且各自单谱号的情况；三声部或更复杂的拆分模式不在覆盖范围内。
