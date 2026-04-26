# Generation Metadata

## Run info
| Item | Value |
| --- | --- |
| Commit hash | d751203a45ef93d9771fd2705556c66d7e5cf55b |
| Branch name | crh1 |
| Generated at | 2026-04-26T17:31:58+08:00 |
| Output language | Chinese |
| Generation mode | Incremental update via `deepwiki` skill |

## Generated / updated pages
- `INDEX.md`
- `GENERATION.md`
- `data-flow.md`
- `modules/lonelypianist-avp-calibration.md`
- `modules/lonelypianist-avp-tracking.md`
- `modules/lonelypianist-macos.md`
- `modules/lonelypianist-avp.md`
- `modules/piano-dialogue-server.md`
- `assets/.gitkeep`

## Existing pages retained
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
- `modules/lonelypianist-macos-runtime.md`
- `modules/lonelypianist-macos-mapping.md`
- `modules/lonelypianist-macos-recording.md`
- `modules/lonelypianist-macos-dialogue.md`
- `modules/lonelypianist-avp-library.md`
- `modules/lonelypianist-avp-calibration.md`
- `modules/lonelypianist-avp-musicxml.md`
- `modules/lonelypianist-avp-tracking.md`
- `modules/lonelypianist-avp-practice.md`
- `modules/piano-dialogue-server-protocol.md`
- `modules/piano-dialogue-server-inference.md`
- `modules/piano-dialogue-server-debug.md`

## Copied assets
- None. `.github/deepwiki/assets/` remains reserved for future diagrams or screenshots.

## Evidence used
- `LonelyPianist.xcodeproj/xcshareddata/xcschemes/LonelyPianistAVP.xcscheme` for shared scheme availability.
- Existing deepwiki pages and module boundaries (to locate broken links).
- `LonelyPianistAVP/ViewModels/ARGuideViewModel.swift` for `CalibrationPhase`, pinch-confirm capture, and guided-flow transitions.
- `LonelyPianistAVP/Services/Calibration/CalibrationPointCaptureService.swift` for reticle stability thresholds and readiness.
- `LonelyPianistAVP/Services/Tracking/ARTrackingService.swift` for left/right hand tip extraction and pinch inputs.
- `LonelyPianistAVP/Views/CalibrationStepView.swift` for Step 1 UI flow and immersive open/close behavior.
- `LonelyPianistAVP/Views/ImmersiveView.swift` and `LonelyPianistAVP/Services/RealityKit/CalibrationOverlayController.swift` for reticle overlay visibility rules.

## Key updates in this generation
| Area | Update |
| --- | --- |
| Deepwiki hygiene | Fixed broken intra-module links, added `.github/deepwiki/assets/` placeholder, and refreshed generation metadata. |
| AVP Step 1 calibration | Updated calibration module page to match current A0/C8 hand roles (reticle input + pinch-confirm), completion-page recalibration entry, overlay visibility, and 5mm stability threshold. |

## Current Coverage Gaps
- Python smoke tests are not yet part of GitHub Actions.
- There is no unified release workflow.
- There is no full macOS -> Python -> AVP end-to-end automated test.
- AVP simulator tests are validated in Actions, but real Vision Pro hand tracking and light-beam comfort still require manual device testing.

## Validation checklist
- [x] Module overview pages no longer contain broken `modules/...` sibling links.
- [x] `.github/deepwiki/assets/` directory exists and is tracked.
- [x] `GENERATION.md` matches the current branch/commit and updated page list.
