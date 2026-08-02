import Foundation
import MusicXML

public enum PracticeFeedbackEventKind: Equatable, Sendable {
    case retryInvitation(issue: PracticeIssueKind)
    case measurePitchStepsStable
    case passagePitchStepsStable
    case roundSummaryReady
}

public struct PracticeFeedbackEvent: Equatable, Sendable {
    public let sequence: Int
    public let sourceMeasureID: PracticeSourceMeasureID?
    public let kind: PracticeFeedbackEventKind

    public init(sequence: Int, sourceMeasureID: PracticeSourceMeasureID?, kind: PracticeFeedbackEventKind) {
        self.sequence = sequence
        self.sourceMeasureID = sourceMeasureID
        self.kind = kind
    }
}

public struct PracticeFeedbackPolicy {
    public init() {}

    public func events(
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
