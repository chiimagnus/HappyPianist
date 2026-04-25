# Generation Metadata

## Run info
| Item | Value |
| --- | --- |
| Commit hash | 3cb80c0eaa078e9133c33b680e4b8f3dad4af5f8 |
| Branch name | main |
| Generated at | 2026-04-25T04:30:00+09:00 |
| Output language | Chinese |
| Generation mode | Incremental update via `deepwiki` skill |

## Generated / updated pages
- `INDEX.md`
- `GENERATION.md`
- `overview.md`
- `architecture.md`
- `data-flow.md`
- `configuration.md`
- `testing.md`
- `workflow.md`
- `troubleshooting.md`
- `modules/lonelypianist-avp-practice.md`

## Existing pages retained
- `business-context.md`
- `dependencies.md`
- `storage.md`
- `glossary.md`
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
- `modules/piano-dialogue-server.md`
- `modules/piano-dialogue-server-protocol.md`
- `modules/piano-dialogue-server-inference.md`
- `modules/piano-dialogue-server-debug.md`

## Copied assets
- None. `.github/deepwiki/assets/` remains reserved for future diagrams or screenshots.

## Evidence used
- Top-level `README.md` product framing and repository layout.
- `.github/workflows/pr-tests.yml` for PR-only macOS / AVP split Xcode tests.
- `.github/workflows/swift-quality.yml` for manual-only SwiftFormat / SwiftLint autocorrect.
- `LonelyPianistAVP/Services/RealityKit/PianoGuideOverlayController.swift` for light-beam AR guide implementation.
- Existing deepwiki pages and module boundaries.
- Recent PR #45 result: PR-only split Xcode workflow merged, with macOS and AVP tests validated through GitHub Actions.

## Key updates in this generation
| Area | Update |
| --- | --- |
| CI | Replaced outdated “no CI” statements with current PR Tests / Swift Quality workflow facts. |
| Testing | Documented `macos-26`, Xcode 26.2 / Swift 6.2 requirements, macOS tests, AVP simulator tests, and `build-for-testing` vs `test`. |
| AVP practice | Updated practice guide to `PianoKeyboardGeometry` + warm-gold prism beams (four-side atlas), replacing legacy key regions + cylinder wording. |
| Configuration | Added PR path filters, workflow permissions, SwiftFormat/SwiftLint config, and AVP simulator destination notes. |
| Troubleshooting | Added package graph, simulator destination, AVP runtime latency, Swift Quality, and light-beam diagnostics. |
| Index | Added `ci-first` reading path and current automation facts. |

## Current Coverage Gaps
- Python smoke tests are not yet part of GitHub Actions.
- There is no unified release workflow.
- There is no full macOS -> Python -> AVP end-to-end automated test.
- AVP simulator tests are validated in Actions, but real Vision Pro hand tracking and light-beam comfort still require manual device testing.

## Validation checklist
- [x] Core pages updated where CI / testing / AVP guide facts changed.
- [x] `INDEX.md` updated with CI-first path and current automation facts.
- [x] `GENERATION.md` updated with branch, commit, language, page list, and gaps.
- [x] AVP light-beam implementation documented in module page.
- [x] Deprecated “no CI” and “AVP scheme not validated” statements removed from updated pages.
