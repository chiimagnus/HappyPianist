# Generation Metadata

## Run info
| Item | Value |
| --- | --- |
| Commit hash | 20e66cb6a38734e262ad9a09f280b6552ace249e |
| Branch name | crh1 |
| Generated at | 2026-05-12T13:00:04+08:00 |
| Output language | Chinese |
| Generation mode | Incremental update via `deepwiki` skill |

## Key updates in this generation
| Area | Update |
| --- | --- |
| AVP 主流程重构同步 | 更新 deepwiki 以反映 `AppRouter.route` root 切换、`FlowState` 持有钢琴类型与曲目/steps、`AppState` 聚合 tracking/runtime calibration，并移除旧的 `ContentView/HomeViewModel/AppModel` 表述。 |
| 曲库 seed/seeder 清理 | 曲库改为“内置条目（bundle）+ 用户导入索引”合并展示；移除 `SongLibrarySeeder` 相关过期描述。 |
| README 对齐 | 更新仓库根 `README.md` 与 `LonelyPianistAVP/README.md` 的 AVP 主流程说明（类型选择 → 准备 → 曲库 → 练习）。 |
| AVP BLE MIDI 模式落地 | 同步 deepwiki 以反映 `.realBluetoothMIDI` 作为独立钢琴模式：系统连接 gate（sources>0）、MIDI-only 注入链路（不启音频识别/hand tracking consumer）、G1 事件模型与 take/phrase 录制输入迁移、以及 Vision Pro 真机冒烟清单。 |

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
