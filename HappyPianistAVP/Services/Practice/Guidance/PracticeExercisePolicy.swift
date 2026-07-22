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
            referenceUse: CoachingReferenceUse?
        ) = switch issue.kind {
        case .pitch:
            (.pitchAccuracy, 0.7, 3, .manualReplay)
        case .onset:
            (.onsetAlignment, 0.75, 3, .manualReplay)
        case .chordSpread:
            (.chordSynchronization, 0.65, 3, .manualReplay)
        case .duration:
            (.durationControl, 0.75, 3, .score)
        case .articulation:
            (.articulationControl, 0.8, 3, .manualReplay)
        case .voicing:
            (.voiceBalance, 0.7, 4, .score)
        case .dynamicContour:
            (.dynamicShaping, 0.8, 3, .score)
        case .pedal:
            (.pedalCoordination, 0.75, 3, .score)
        case .tempo:
            (.tempoStability, 0.8, 4, .manualReplay)
        case .phrase:
            (.phraseContinuity, 0.8, 3, .score)
        case .evidence:
            (.evidenceCheck, nil, 1, nil)
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
            voiceFocus: issue.kind == .voicing ? voiceFocus(in: relevantEvents) : nil,
            repeatCount: specification.repeatCount,
            referenceUse: specification.referenceUse,
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

    private func voiceFocus(in events: [ScorePerformanceNoteEvent]) -> CoachingVoiceFocus? {
        let grouped = Dictionary(grouping: events) {
            CoachingVoiceFocus(
                partID: $0.sourceNoteID.partID,
                staff: $0.staff,
                voice: $0.voice
            )
        }
        guard grouped.count > 1 else { return nil }
        let targets = grouped.map { focus, notes in
            let mean = notes.map { Double($0.velocity) }.reduce(0, +) / Double(notes.count)
            return (focus, mean)
        }
        guard let highest = targets.map(\.1).max() else { return nil }
        let prominent = targets.filter { $0.1 == highest }
        return prominent.count == 1 ? prominent[0].0 : nil
    }
}
