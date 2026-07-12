import Foundation

enum PracticeFeedbackEventKind: Equatable, Sendable {
    case retryInvitation(issue: PracticeIssueKind)
    case measureStable
    case passageStable
    case roundSummaryReady
}

struct PracticeFeedbackEvent: Equatable, Sendable {
    let identity: PracticeSongIdentity
    let sessionGeneration: Int
    let roundGeneration: Int
    let sourceMeasureID: PracticeSourceMeasureID?
    let kind: PracticeFeedbackEventKind
}

struct PracticeFeedbackPolicy {
    func events(
        for fact: PracticeSessionFact?,
        previousProgress: SongPracticeProgress?,
        progress: SongPracticeProgress,
        sessionGeneration: Int,
        passageSourceMeasureIDs: Set<PracticeSourceMeasureID>
    ) -> [PracticeFeedbackEvent] {
        guard let fact else { return [] }
        switch fact {
        case let .attemptIssue(attempt, issue):
            return [event(attempt: attempt, sessionGeneration: sessionGeneration, kind: .retryInvitation(issue: issue))]
        case let .attemptMatched(attempt):
            let id = attempt.occurrenceID.sourceMeasureID
            guard state(of: id, handMode: attempt.handMode, in: previousProgress) != .stable,
                  state(of: id, handMode: attempt.handMode, in: progress) == .stable
            else { return [] }
            return [event(attempt: attempt, sessionGeneration: sessionGeneration, kind: .measureStable)]
        case .passageRestarted:
            return []
        case let .passageCompleted(round):
            let passageFacts = progress.measureFacts.filter {
                $0.handMode == round.handMode && passageSourceMeasureIDs.contains($0.sourceMeasureID)
            }
            let stable = PracticePassageCoverage.isStable(
                facts: passageFacts,
                sourceMeasureIDs: passageSourceMeasureIDs
            )
            return [
                PracticeFeedbackEvent(
                    identity: round.identity,
                    sessionGeneration: sessionGeneration,
                    roundGeneration: round.roundGeneration,
                    sourceMeasureID: nil,
                    kind: stable ? .passageStable : .roundSummaryReady
                )
            ]
        }
    }

    private func state(
        of id: PracticeSourceMeasureID,
        handMode: PracticeHandMode,
        in progress: SongPracticeProgress?
    ) -> MeasureLearningState? {
        progress?.measureFacts.first { $0.sourceMeasureID == id && $0.handMode == handMode }?.state
    }

    private func event(
        attempt: PracticeAttemptFact,
        sessionGeneration: Int,
        kind: PracticeFeedbackEventKind
    ) -> PracticeFeedbackEvent {
        PracticeFeedbackEvent(
            identity: attempt.identity,
            sessionGeneration: sessionGeneration,
            roundGeneration: attempt.roundGeneration,
            sourceMeasureID: attempt.occurrenceID.sourceMeasureID,
            kind: kind
        )
    }
}
