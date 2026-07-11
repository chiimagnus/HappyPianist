import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func feedbackPolicyPublishesTypedRetryAndRejectsInsufficientEvidence() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 1)
    let attempt = PracticeAttemptFact(
        identity: identity,
        roundGeneration: 4,
        occurrenceID: PracticeMeasureOccurrenceID(sourceMeasureID: source, occurrenceIndex: 1),
        stepIndex: 2,
        handMode: .both,
        tempoScale: 0.8,
        timestamp: .now
    )
    let progress = SongPracticeProgress(identity: identity, updatedAt: .now)

    let events = PracticeFeedbackPolicy().events(
        for: .attemptIssue(attempt, issue: .wrongNote),
        previousProgress: nil,
        progress: progress,
        sessionGeneration: 7
    )

    #expect(events == [PracticeFeedbackEvent(
        identity: identity,
        sessionGeneration: 7,
        roundGeneration: 4,
        sourceMeasureID: source,
        kind: .retryInvitation(issue: .wrongNote)
    )])
    #expect(PracticeFeedbackPolicy().events(for: nil, previousProgress: nil, progress: progress, sessionGeneration: 7).isEmpty)
}

@Test
func feedbackCopyHasNoPunitiveTerms() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let id = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 11, sourceNumberToken: "12A")
    let copy = PracticeIssueKind.allCasesForFeedbackTest.map { issue in
        PracticeFeedbackCuePresentation(event: PracticeFeedbackEvent(
            identity: identity,
            sessionGeneration: 1,
            roundGeneration: 1,
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
func measureStableUsesSourceAndHandCompositeIdentity() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let id = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let attempt = PracticeAttemptFact(
        identity: identity,
        roundGeneration: 1,
        occurrenceID: PracticeMeasureOccurrenceID(sourceMeasureID: id, occurrenceIndex: 0),
        stepIndex: 0,
        handMode: .right,
        tempoScale: 0.8,
        timestamp: .now
    )
    let left = MeasurePracticeFacts(sourceMeasureID: id, handMode: .left, state: .stable)
    let rightLearning = MeasurePracticeFacts(sourceMeasureID: id, handMode: .right, state: .learning)
    let rightStable = MeasurePracticeFacts(sourceMeasureID: id, handMode: .right, state: .stable)
    let previous = SongPracticeProgress(identity: identity, measureFacts: [left, rightLearning], updatedAt: .now)
    let current = SongPracticeProgress(identity: identity, measureFacts: [left, rightStable], updatedAt: .now)
    let events = PracticeFeedbackPolicy().events(
        for: .attemptMatched(attempt), previousProgress: previous, progress: current, sessionGeneration: 1
    )
    #expect(events.map(\.kind) == [.measureStable])
}
