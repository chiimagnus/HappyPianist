# Generation Metadata

## Run info

| Item | Value |
| --- | --- |
| Repository | archive snapshot |
| Source archive | `HappyPianist-20260722-180030.zip` |
| Source commit | unavailable (`.git` was not included) |
| Local snapshot baseline | `621505b58b97a39362722e970bd28ba7494dd5aa` |
| Generated at | 2026-07-22T10:06:08Z |
| Output language | Chinese |
| Generation mode | Canonical documentation reconciliation with `neat-freak` |

## Canonical pages

- `AGENTS.md`
- `README.md`
- `docs/overview.md`
- `docs/architecture.md`
- `docs/data-flow.md`
- `docs/piano-performance-quality.md`
- `docs/configuration.md`
- `docs/storage.md`
- `docs/modules/happypianist-avp.md`
- `docs/modules/happypianist-avp-practice.md`
- `docs/testing/core-function-checklist.md`
- `docs/testing/piano-performance-validation.md`

## Reconciliation summary

- Reconciled the runtime chain from `PerformanceObservation` through bounded alignment, capability-aware assessment, `MusicalIssue`, and one `CoachingAction`.
- Replaced the obsolete failed-count hotspot description with the product path that consumes `CoachingDecisionService` while retaining a basic typed-issue retry fallback.
- Clarified target, hand and fingering provenance, evidence-check degradation, accept/skip/remeasure instrumentation, and the runtime-only persistence boundary.
- Extended architecture and validation entry points without adding a new documentation page.

## Coverage gaps

- The archive did not include `.git`; the original source commit and an exact diff from the previous generation commit could not be verified.
- `xcodebuild test`, visionOS Simulator and Apple Vision Pro were not run during this documentation-only pass.
- Real-device latency, listening quality, expert agreement and teaching effectiveness remain external evidence gates.
