import Foundation

enum PracticeFeedbackEventKind: Equatable {
    case retryInvitation(issue: PracticeIssueKind)
    case measurePitchStepsStable
    case passagePitchStepsStable
    case roundSummaryReady
}

struct PracticeFeedbackEvent: Equatable {
    let sequence: Int
    let sourceMeasureID: PracticeSourceMeasureID?
    let kind: PracticeFeedbackEventKind
}

struct PracticeFeedbackPolicy {
    func events(
        for fact: PracticeSessionFact?,
        previousProgress: SongPracticeProgress?,
        progress: SongPracticeProgress,
        eventSequence: Int,
        passageSourceMeasureIDs: Set<PracticeSourceMeasureID>,
        coachingDecision: CoachingDecision? = nil
    ) -> [PracticeFeedbackEvent] {
        guard let fact else { return [] }
        switch fact {
        case let .attemptIssue(sourceMeasureID, issue):
            guard suppressesUncertainPitchRetry(
                issue: issue,
                sourceMeasureID: sourceMeasureID,
                coachingDecision: coachingDecision
            ) == false else { return [] }
            return [event(sequence: eventSequence, sourceMeasureID: sourceMeasureID, kind: .retryInvitation(issue: issue))]
        case let .attemptMatched(sourceMeasureID, handMode):
            guard state(of: sourceMeasureID, handMode: handMode, in: previousProgress) != .pitchStepStable,
                  state(of: sourceMeasureID, handMode: handMode, in: progress) == .pitchStepStable
            else { return [] }
            return [event(
                sequence: eventSequence,
                sourceMeasureID: sourceMeasureID,
                kind: .measurePitchStepsStable
            )]
        case let .passageCompleted(handMode):
            let passageFacts = progress.measureFacts.filter {
                $0.handMode == handMode && passageSourceMeasureIDs.contains($0.sourceMeasureID)
            }
            let hasStablePitchSteps = PracticePassageCoverage.hasStablePitchSteps(
                facts: passageFacts,
                sourceMeasureIDs: passageSourceMeasureIDs
            )
            return [
                event(
                    sequence: eventSequence,
                    sourceMeasureID: nil,
                    kind: hasStablePitchSteps && coachingDecision == nil
                        ? .passagePitchStepsStable
                        : .roundSummaryReady
                ),
            ]
        }
    }

    private func suppressesUncertainPitchRetry(
        issue: PracticeIssueKind,
        sourceMeasureID: PracticeSourceMeasureID,
        coachingDecision: CoachingDecision?
    ) -> Bool {
        guard issue == .wrongNote,
              let coachingDecision,
              coachingDecision.action.kind == .evidenceCheck,
              case let .evidenceAvailable(dimension) = coachingDecision.action.completionCondition.target,
              [.exactPitch, .extraNotes, .missingNotes].contains(dimension)
        else { return false }
        let sourceIDs = coachingDecision.issue.measureOccurrenceIDs.map(\.sourceMeasureID)
        return sourceIDs.isEmpty || sourceIDs.contains(sourceMeasureID)
    }

    private func state(
        of id: PracticeSourceMeasureID,
        handMode: PracticeHandMode,
        in progress: SongPracticeProgress?
    ) -> MeasurePitchStepLearningState? {
        progress?.measureFacts.first { $0.sourceMeasureID == id && $0.handMode == handMode }?.state
    }

    private func event(
        sequence: Int,
        sourceMeasureID: PracticeSourceMeasureID?,
        kind: PracticeFeedbackEventKind
    ) -> PracticeFeedbackEvent {
        PracticeFeedbackEvent(
            sequence: sequence,
            sourceMeasureID: sourceMeasureID,
            kind: kind
        )
    }
}
