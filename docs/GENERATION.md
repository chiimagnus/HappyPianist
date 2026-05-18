# Generation Metadata

## Run info
| Item | Value |
| --- | --- |
| Commit hash | d08960c |
| Branch name | crh |
| Generated at | 2026-05-16T15:52:16+08:00 |
| Output language | Chinese |
| Generation mode | Incremental update via `neat-freak` (docs-as-canonical) |

## Key updates in this generation
| Area | Update |
| --- | --- |
| AVP tests（DI / composition） | 同步 visionOS 测试到新的依赖注入/组合方式：测试更倾向于显式构建 `PianoModeRegistryService` / `PracticeSessionViewModelFactoryService`，并用测试侧 convenience init 或 fake/noop services 隔离外部依赖。 |
| Testing 文档刷新 | `testing.md` 增补 AVP tests 的 DI 约定与代表测试入口（router/virtual piano/manual advance 等），避免文档与测试实现漂移。 |

## Generated page list
### Core pages
- `INDEX.md`
- `business-context.md`
- `overview.md`
- `architecture.md`
- `dependencies.md`
- `data-flow.md`
- `configuration.md`
- `storage.md`
- `testing.md`
- `workflow.md`
- `troubleshooting.md`
- `glossary.md`
- `Fallbacks.md`
- `GENERATION.md`

### Module pages (`modules/`)
- `modules/lonelypianist-macos.md`
- `modules/lonelypianist-macos-runtime.md`
- `modules/lonelypianist-macos-mapping.md`
- `modules/lonelypianist-macos-recording.md`
- `modules/lonelypianist-macos-dialogue.md`
- `modules/lonelypianist-avp.md`
- `modules/lonelypianist-avp-library.md`
- `modules/lonelypianist-avp-calibration.md`
- `modules/lonelypianist-avp-musicxml.md`
- `modules/lonelypianist-avp-tracking.md`
- `modules/lonelypianist-avp-practice.md`
- `modules/lonelypianist-avp-practice-audio.md`
- `modules/piano-dialogue-server.md`
- `modules/piano-dialogue-server-protocol.md`
- `modules/piano-dialogue-server-inference.md`
- `modules/piano-dialogue-server-debug.md`

## Copied asset list
- None (no files under `assets/`).

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
