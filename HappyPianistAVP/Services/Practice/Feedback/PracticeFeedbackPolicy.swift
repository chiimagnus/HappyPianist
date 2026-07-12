import Foundation

enum PracticeFeedbackEventKind: Equatable, Sendable {
    case retryInvitation(issue: PracticeIssueKind)
    case measureStable
    case passageStable
    case roundSummaryReady
}

struct PracticeFeedbackEvent: Equatable, Sendable {
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
        passageSourceMeasureIDs: Set<PracticeSourceMeasureID>
    ) -> [PracticeFeedbackEvent] {
        guard let fact else { return [] }
        switch fact {
        case let .attemptIssue(sourceMeasureID, issue):
            return [event(sequence: eventSequence, sourceMeasureID: sourceMeasureID, kind: .retryInvitation(issue: issue))]
        case let .attemptMatched(sourceMeasureID, handMode):
            guard state(of: sourceMeasureID, handMode: handMode, in: previousProgress) != .stable,
                  state(of: sourceMeasureID, handMode: handMode, in: progress) == .stable
            else { return [] }
            return [event(sequence: eventSequence, sourceMeasureID: sourceMeasureID, kind: .measureStable)]
        case let .passageCompleted(handMode):
            let passageFacts = progress.measureFacts.filter {
                $0.handMode == handMode && passageSourceMeasureIDs.contains($0.sourceMeasureID)
            }
            let stable = PracticePassageCoverage.isStable(
                facts: passageFacts,
                sourceMeasureIDs: passageSourceMeasureIDs
            )
            return [
                event(
                    sequence: eventSequence,
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
