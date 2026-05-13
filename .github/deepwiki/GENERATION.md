# Generation Metadata

## Run info
| Item | Value |
| --- | --- |
| Commit hash | 93903598c6fe8b1ed2836e5b8791493d8cdb1b1b |
| Branch name | crh2 |
| Generated at | 2026-05-13T20:00:00+08:00 |
| Output language | Chinese |
| Generation mode | Incremental update via `deepwiki` skill |

## Key updates in this generation
| Area | Update |
| --- | --- |
| PianoKind → PianoModeProtocol 全面迁移 | 将 deepwiki 中所有 `PianoKind` 枚举引用替换为 `PianoModeProtocol` 协议 + `PianoModeRegistryService` 注册表；三种模式（RealAudio / BluetoothMIDI / Virtual）通过协议实现注册。 |
| AVP BLE MIDI 录制链路 | 新增 BLE MIDI 数据流文档：`BluetoothMIDIInputEventSourceService` → `MIDIRecordingAdapter` → `RecordingTakeRecorder` → `RecordingTakeStore`（takes.json）；补充 Take 录制/回放/Phrase 录制的存储与数据流描述。 |
| AVP 目录地图扩充 | `modules/lonelypianist-avp.md` 目录地图从 12 项扩充至 ~30 项，覆盖全部 Services 子目录（AppFlow/、Audio/、AudioRecognition/、Bluetooth/、MIDI/、Recording/、Networking/、Practice/ 等）。 |
| architecture.md 组件边界 | 新增 5 个组件边界条目（PianoModeRegistryService、BluetoothMIDIInputEventSourceService、MIDIRecordingAdapter、RecordingTakeStore、TakePlaybackController）和 3 个关键契约（PracticeInputEvent、RecordingTake/RecordingTakeEvent、PianoModeProtocol）。 |
| storage.md Take 存储 | 新增 AVP Take 录制存储段落：路径、JSON 格式、编码、写入时机、事件类型、回放链路。 |
| glossary.md 术语更新 | 替换 PianoKind 为 PianoModeProtocol/PianoModeRegistryService；补充 `RecordingTake` 存储术语；修正 `GenerateParams.strategy` 遗漏 `rule` 第三策略。 |

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
