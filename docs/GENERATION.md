# Generation Metadata

## Run info
| Item | Value |
| --- | --- |
| Commit hash | 44e8eb0 |
| Branch name | crh1 |
| Generated at | 2026-05-18T22:53:50+08:00 |
| Output language | Chinese |
| Generation mode | Incremental update via `neat-freak` (docs-as-canonical) |

## Key updates in this generation
| Area | Update |
| --- | --- |
| BLE MIDI step 判定 | BLE MIDI 输入改为 multicast，并在 Step 3 使用 `MIDIPracticeStepMatcher` 做 deterministic step advance；为排查事件分流加入 `debugEventID` 日志链路。 |
| INDEX 移除 | 删除 `docs/INDEX.md`，把「按问题导航」迁移到 `docs/overview.md`。 |
| Overview 合并 | 把 `docs/business-context.md` 的剩余有效信息合并进 `docs/overview.md`，并删除 `docs/business-context.md`。 |
| Architecture 去重 | `docs/architecture.md` 用“按模块入口”替代组件长表，并移除重复的 CI/Actions 段落。 |
| Testing 移除 | 删除 `docs/testing.md`，把“本地验证命令”收敛进 `docs/overview.md`。 |
| Troubleshooting 移除 | 删除 `docs/troubleshooting.md`（故障定位按模块页/README 自行下钻）。 |
| Workflow 移除 | 删除 `docs/workflow.md`，把“本地验证命令”收敛进 `docs/overview.md`。 |
| Modules 精简 | `docs/modules/` 合并为 4 页：`lonelypianist-macos.md`、`lonelypianist-avp.md`、`lonelypianist-avp-practice.md`、`piano-dialogue-server.md`。 |

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
