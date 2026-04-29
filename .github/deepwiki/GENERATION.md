# Generation Metadata

## Run info
| Item | Value |
| --- | --- |
| Commit hash | 8017dc1e595db21f40dfa6aabe2aa031241f0e47 |
| Branch name | crh2 |
| Generated at | 2026-04-29T16:06:42+08:00 |
| Output language | Chinese |
| Generation mode | Incremental update via `deepwiki` skill |

## Key updates in this generation
| Area | Update |
| --- | --- |
| Step 3 practice UX | Documented `PracticeState.ready` semantics (enter without auto-start; first “Next” begins) and corrected practice-audio backend object names. |
| Audio troubleshooting | Added mapping for common audio-recognition logs (`audio service stopped`, `failed start generation`, RemoteIO -10851) and linked the “Next short note” investigation page from troubleshooting. |
| Log noise reduction | Reflected `stopAudioRecognition()` stop-log gating so “stopped” spam no longer misleads audio playback debugging. |
| Glossary | Added `PracticeState` entry clarifying `idle/ready/guiding/completed` semantics. |

## Current Coverage Gaps
- Python smoke tests are not yet part of GitHub Actions.
- There is no unified release workflow.
- There is no full macOS -> Python -> AVP end-to-end automated test.
- PR Tests workflow has been deleted; all tests must be run manually.
- Audio recognition fallback behavior and performance tuning still requires real-device verification.
- Audio recognition engine failures (e.g., RemoteIO -10851) are still environment-dependent; simulator behavior is not a reliable proxy for Vision Pro devices.
- AutoplayPerformanceTimeline complex edge cases (e.g., simultaneous pedal up/down) may need more test coverage.
