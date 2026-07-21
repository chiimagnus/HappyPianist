import Foundation
@testable import HappyPianistAVP
import Testing

private let focusBuilder = SongPracticeFocusMeasureBuilder()

@Test
func focusBuilderUsesDeterministicLexicographicRankingAndLimit() {
    let progress = focusProgress([
        focusFact(0, failed: 1, attemptedAt: 10),
        focusFact(1, failed: 9, attemptedAt: 40),
        focusFact(2, issue: .wrongNote, failed: 1, attemptedAt: 5),
        focusFact(3, failed: 9, attemptedAt: 30),
    ])

    #expect(focusBuilder.build(from: progress) == [
        SongPracticeFocusMeasure(
            sourceMeasureID: focusSource(2),
            reason: .recentIssue(.wrongNote)
        ),
        SongPracticeFocusMeasure(
            sourceMeasureID: focusSource(1),
            reason: .failedAttempts(9)
        ),
        SongPracticeFocusMeasure(
            sourceMeasureID: focusSource(3),
            reason: .failedAttempts(9)
        ),
    ])
}

@Test
func focusBuilderExcludesStableBothOrStableSeparateHands() {
    let progress = focusProgress([
        focusFact(0, hand: .both, state: .pitchStepStable, attemptedAt: 10),
        focusFact(1, hand: .left, state: .pitchStepStable, attemptedAt: 10),
        focusFact(1, hand: .right, state: .pitchStepStable, attemptedAt: 11),
        focusFact(2, hand: .left, state: .pitchStepStable, attemptedAt: 12),
    ])

    #expect(focusBuilder.build(from: progress) == [
        SongPracticeFocusMeasure(
            sourceMeasureID: focusSource(2),
            reason: .learning
        ),
    ])
}

@Test
func focusBuilderMergesHandsAndKeepsOnlyFactsItCanProve() {
    let progress = focusProgress([
        focusFact(0, hand: .left, failed: 2, attemptedAt: 10),
        focusFact(0, hand: .right, issue: .incompleteChord, failed: 3, attemptedAt: 20),
    ])

    #expect(focusBuilder.build(from: progress) == [
        SongPracticeFocusMeasure(
            sourceMeasureID: focusSource(0),
            reason: .recentIssue(.incompleteChord)
        ),
    ])
}

@Test
func focusBuilderIsOrderIndependentAndUsesSourceIdentityTieBreak() {
    let sourceA = PracticeSourceMeasureID(partID: "P|1", sourceMeasureIndex: 2)
    let sourceB = PracticeSourceMeasureID(partID: "P", sourceMeasureIndex: 1, sourceNumberToken: "2|")
    let facts = [
        MeasurePracticeFacts(
            sourceMeasureID: sourceA,
            handMode: .both,
            state: .learning,
            failedAttempts: 1,
            lastAttemptAt: Date(timeIntervalSince1970: 10)
        ),
        MeasurePracticeFacts(
            sourceMeasureID: sourceB,
            handMode: .both,
            state: .learning,
            failedAttempts: 1,
            lastAttemptAt: Date(timeIntervalSince1970: 10)
        ),
    ]

    let forward = focusBuilder.build(from: focusProgress(facts))
    let reversed = focusBuilder.build(from: focusProgress(Array(facts.reversed())))
    #expect(forward == reversed)
    #expect(forward.map(\.sourceMeasureID) == [sourceB, sourceA])
}

@Test
func focusBuilderReturnsEmptyWithoutCurrentAttemptFacts() {
    #expect(focusBuilder.build(from: nil).isEmpty)
    #expect(focusBuilder.build(from: focusProgress([
        MeasurePracticeFacts(sourceMeasureID: focusSource(0), handMode: .both),
    ])).isEmpty)
}

private func focusProgress(_ facts: [MeasurePracticeFacts]) -> SongPracticeProgress {
    SongPracticeProgress(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "current"),
        measureFacts: facts,
        updatedAt: Date(timeIntervalSince1970: 100)
    )
}

private func focusFact(
    _ index: Int,
    hand: PracticeHandMode = .both,
    state: MeasurePitchStepLearningState = .learning,
    issue: PracticeIssueKind? = nil,
    failed: Int = 0,
    attemptedAt: TimeInterval
) -> MeasurePracticeFacts {
    MeasurePracticeFacts(
        sourceMeasureID: focusSource(index),
        handMode: hand,
        state: state,
        successfulAttempts: state == .pitchStepStable ? 1 : 0,
        failedAttempts: failed,
        recentIssue: issue,
        lastAttemptAt: Date(timeIntervalSince1970: attemptedAt)
    )
}

private func focusSource(_ index: Int) -> PracticeSourceMeasureID {
    PracticeSourceMeasureID(
        partID: "P1",
        sourceMeasureIndex: index,
        sourceNumberToken: "\(index + 1)"
    )
}
