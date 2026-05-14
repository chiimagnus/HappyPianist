# Generation Metadata

## Run info
| Item | Value |
| --- | --- |
| Commit hash | 71f8bc0fbc6a330e7a7a3e9696da7238c3b2bc5c |
| Branch name | crh2 |
| Generated at | 2026-05-14T11:17:03+08:00 |
| Output language | Chinese |
| Generation mode | Incremental update via `deepwiki` skill |

## Key updates in this generation
| Area | Update |
| --- | --- |
| 左右手语义（ScoreHand）贯穿链路 | 补齐 `ScoreHand` 从 staff 推导的语义，并在 deepwiki 中明确其贯穿 steps / guides / 2D 键盘 / 3D decal / 判定 gate 的数据流与排障抓手。 |
| 单谱表 MusicXML 自动分手 | 更新 MusicXML 导入管线文档：通过 `MusicXMLHandRouter` 对缺失 staff 的单谱表 score deterministic 补 `staff=1/2`，并明确触发条件与阈值策略；同时注明当前不提供回退/override。 |
| 五线谱迁移为 Grand Staff | 更新 Practice 模块文档：五线谱视图从旧滚动单谱表迁移为 `GrandStaffNotationView`（上下双谱表），并补充 layout 输入/输出与能力边界。 |
| 练习判定开关：左右手分别满足 | 文档化 `practiceHandSeparatedStepMatchingEnabled` 开关（默认关闭），说明开启后左右手 expected 需分别满足，并指出 press/音频/BLE MIDI 三路径的一致实现。 |
| 测试与命令事实刷新 | 修正 visionOS 测试必须使用 concrete simulator destination id，并更新 testing/config/index 等页面的命令与说明。 |

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
