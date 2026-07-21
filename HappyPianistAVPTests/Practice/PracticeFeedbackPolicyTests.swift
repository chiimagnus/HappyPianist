import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func feedbackPolicyPublishesTypedRetryAndRejectsMissingFact() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 1)
    let progress = SongPracticeProgress(identity: identity, updatedAt: .now)

    let events = PracticeFeedbackPolicy().events(
        for: .attemptIssue(sourceMeasureID: source, issue: .wrongNote),
        previousProgress: nil,
        progress: progress,
        eventSequence: 1,
        passageSourceMeasureIDs: [source]
    )

    #expect(events == [PracticeFeedbackEvent(
        sequence: 1,
        sourceMeasureID: source,
        kind: .retryInvitation(issue: .wrongNote)
    )])
    #expect(PracticeFeedbackPolicy().events(
        for: nil,
        previousProgress: nil,
        progress: progress,
        eventSequence: 2,
        passageSourceMeasureIDs: [source]
    ).isEmpty)
}

@Test
func feedbackCopyHasNoPunitiveTerms() {
    let id = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 11, sourceNumberToken: "12A")
    let copy = PracticeIssueKind.allCasesForFeedbackTest.map { issue in
        PracticeFeedbackCuePresentation(event: PracticeFeedbackEvent(
            sequence: 1,
            sourceMeasureID: id,
            kind: .retryInvitation(issue: issue)
        )).title
    }
    let punitiveTerms = ["失败", "扣分", "错误太多", "差"]
    #expect(copy.allSatisfy { text in punitiveTerms.allSatisfy { text.localizedStandardContains($0) == false } })
    #expect(copy.allSatisfy { $0.localizedStandardContains("12A") })
}

private extension PracticeIssueKind {
    static let allCasesForFeedbackTest: [Self] = [.wrongNote, .missedNote, .incompleteChord]
}

@Test
func measurePitchStepStabilityUsesSourceAndHandCompositeIdentity() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let id = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let left = MeasurePracticeFacts(sourceMeasureID: id, handMode: .left, state: .pitchStepStable)
    let rightLearning = MeasurePracticeFacts(sourceMeasureID: id, handMode: .right, state: .learning)
    let rightStable = MeasurePracticeFacts(sourceMeasureID: id, handMode: .right, state: .pitchStepStable)
    let previous = SongPracticeProgress(identity: identity, measureFacts: [left, rightLearning], updatedAt: .now)
    let current = SongPracticeProgress(identity: identity, measureFacts: [left, rightStable], updatedAt: .now)
    let events = PracticeFeedbackPolicy().events(
        for: .attemptMatched(sourceMeasureID: id, handMode: .right),
        previousProgress: previous,
        progress: current,
        eventSequence: 1,
        passageSourceMeasureIDs: [id]
    )
    #expect(events.map(\.kind) == [.measurePitchStepsStable])
}

@Test
func passageCompletionUsesResolvedOccurrenceSourceIDs() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let source0 = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let source6 = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 6)
    let unrelated = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 3)
    let progress = SongPracticeProgress(
        identity: identity,
        measureFacts: [
            MeasurePracticeFacts(sourceMeasureID: source0, handMode: .both, state: .pitchStepStable),
            MeasurePracticeFacts(sourceMeasureID: source6, handMode: .both, state: .pitchStepStable),
            MeasurePracticeFacts(sourceMeasureID: unrelated, handMode: .both, state: .learning),
        ],
        updatedAt: .now
    )

    let events = PracticeFeedbackPolicy().events(
        for: .passageCompleted(handMode: .both),
        previousProgress: progress,
        progress: progress,
        eventSequence: 1,
        passageSourceMeasureIDs: [source6, source0]
    )

    #expect(events.map(\.kind) == [.passagePitchStepsStable])
}

@Test
func passageCompletionRequiresEveryExpectedMeasure() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let first = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let second = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 1)
    let progress = SongPracticeProgress(
        identity: identity,
        measureFacts: [MeasurePracticeFacts(sourceMeasureID: first, handMode: .both, state: .pitchStepStable)],
        updatedAt: .now
    )

    let events = PracticeFeedbackPolicy().events(
        for: .passageCompleted(handMode: .both),
        previousProgress: progress,
        progress: progress,
        eventSequence: 1,
        passageSourceMeasureIDs: [first, second]
    )
    #expect(events.map(\.kind) == [.roundSummaryReady])
}

@Test
func repeatedIssueEventsHaveDistinctSequenceIdentity() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let progress = SongPracticeProgress(identity: identity, updatedAt: .now)
    let policy = PracticeFeedbackPolicy()
    let first = policy.events(
        for: .attemptIssue(sourceMeasureID: source, issue: .wrongNote),
        previousProgress: progress,
        progress: progress,
        eventSequence: 1,
        passageSourceMeasureIDs: [source]
    )
    let second = policy.events(
        for: .attemptIssue(sourceMeasureID: source, issue: .wrongNote),
        previousProgress: progress,
        progress: progress,
        eventSequence: 2,
        passageSourceMeasureIDs: [source]
    )
    #expect(first != second)
}
