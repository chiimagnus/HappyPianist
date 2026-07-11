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
    let copy = ["这个音再试一次", "还有一个音在等你", "让和弦一起落下", "这个小节已经点亮"]
    let punitiveTerms = ["失败", "扣分", "错误太多", "差"]
    #expect(copy.allSatisfy { text in punitiveTerms.allSatisfy { text.localizedStandardContains($0) == false } })
}
