import Foundation

struct PracticeExercisePolicy: Sendable {
    func action(
        for issue: MusicalIssue,
        scoreEvents: [ScorePerformanceNoteEvent] = []
    ) -> CoachingAction? {
        guard let dimension = issue.dimensionResults.first?.dimension else { return nil }
        let relevantEvents = scoreEvents.filter { issue.scoreRange.contains($0.performedOnTick) }

        let specification: (
            kind: CoachingActionKind,
            tempoRatio: Double?,
            repeatCount: Int,
            referenceUse: CoachingReferenceUse?,
            cueUse: CoachingCueUse?
        ) = switch issue.kind {
        case .pitch:
            (.pitchAccuracy, 0.7, 3, .manualReplay, nil)
        case .onset:
            (.onsetAlignment, 0.75, 3, .manualReplay, .metronome)
        case .chordSpread:
            (.chordSynchronization, 0.65, 3, .manualReplay, .subdivision)
        case .duration:
            (.durationControl, 0.75, 3, .score, .metronome)
        case .articulation:
            (.articulationControl, 0.8, 3, .manualReplay, nil)
        case .voicing:
            (.voiceBalance, 0.7, 4, .score, .voiceHighlight)
        case .dynamicContour:
            (.dynamicShaping, 0.8, 3, .score, nil)
        case .pedal:
            (.pedalCoordination, 0.75, 3, .score, .pedal)
        case .tempo:
            (.tempoStability, 0.8, 4, .manualReplay, .metronome)
        case .phrase:
            (.phraseContinuity, 0.8, 3, .score, nil)
        case .evidence:
            (.evidenceCheck, nil, 1, nil, nil)
        }

        let completionTarget: CoachingCompletionTarget = if issue.kind == .evidence {
            .evidenceAvailable(dimension: dimension)
        } else {
            .dimensionOutcome(dimension: dimension, outcome: .correct)
        }
        return CoachingAction(
            kind: specification.kind,
            scoreRange: issue.scoreRange,
            tempoRatio: specification.tempoRatio,
            handFocus: handFocus(in: relevantEvents),
            fingerings: relevantEvents.flatMap(\.fingerings),
            repeatCount: specification.repeatCount,
            referenceUse: specification.referenceUse,
            cueUse: specification.cueUse,
            completionCondition: CoachingCompletionCondition(target: completionTarget)
        )
    }

    private func handFocus(in events: [ScorePerformanceNoteEvent]) -> ScoreHandAssignment? {
        guard let first = events.first?.handAssignment,
              first.hand != .unknown,
              events.allSatisfy({ $0.handAssignment == first })
        else {
            return nil
        }
        return first
    }
}
