# Generation Metadata

## Run info
| Item | Value |
| --- | --- |
| Commit hash | d6a5c4ddfba2225ec57c2e1266b649aaa1d3cb32 |
| Branch name | crh2 |
| Generated at | 2026-04-28T15:30:00+08:00 |
| Output language | Chinese |
| Generation mode | Incremental update via `deepwiki` skill |

## Key updates in this generation
| Area | Update |
| --- | --- |
| CI/CD workflow | Reflected deletion of `pr-tests.yml` workflow; tests now require manual local execution. |
| Autoplay timeline | Added comprehensive documentation for `AutoplayPerformanceTimeline` including event types, build flow, and priority rules. |
| Guide construction | Added detailed documentation for `PianoHighlightGuideBuilderService` including build input, key steps, and fallback behavior. |
| Coverage service | Added documentation for `PianoHighlightParsedElementCoverageService` with coverage categories and usage. |
| Audio recognition | Added audio recognition terms and debug hooks; documented harmonic template scoring improvements. |
| Strict prerequisites | Documented autoplay prerequisite checks and UI error messages (tempoMap, guides, pedal, fermata). |
| Fallbacks | Added new `Fallbacks.md`专题页面 documenting all fallback behaviors and their status (eliminated vs. retained). |
| Glossary | Added terms for AutoplayPerformanceTimeline, PianoHighlightGuide, MusicXMLExpressivityOptions, and audio recognition. |

## Current Coverage Gaps
- Python smoke tests are not yet part of GitHub Actions.
- There is no unified release workflow.
- There is no full macOS -> Python -> AVP end-to-end automated test.
- PR Tests workflow has been deleted; all tests must be run manually.
- Audio recognition fallback behavior and performance tuning still requires real-device verification.
- AutoplayPerformanceTimeline complex edge cases (e.g., simultaneous pedal up/down) may need more test coverage.
