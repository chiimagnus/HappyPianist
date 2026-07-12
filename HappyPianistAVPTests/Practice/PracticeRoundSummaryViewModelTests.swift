import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func roundSummaryContainsOnlyOneHotspotAndAction() throws {
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let occurrence = PracticeMeasureOccurrenceID(sourceMeasureID: source, occurrenceIndex: 0)
    let passage = try #require(PracticePassage(start: occurrence, end: occurrence))
    let configuration = PracticeRoundConfiguration(passage: passage, handMode: .both, tempoScale: 0.8, loopEnabled: false, requiredSuccesses: 3)
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let progress = SongPracticeProgress(
        identity: identity,
        activeConfiguration: configuration,
        measureFacts: [feedbackFacts(index: 0, failures: 1, issue: .wrongNote)],
        updatedAt: .now
    )
    let summary = try #require(PracticeRoundSummaryViewModel(
        progress: progress,
        configuration: configuration,
        passageSourceMeasureIDs: [source],
        isFullPassage: true
    ))
    #expect(summary.hotspot?.sourceMeasureID == source)
    #expect(summary.nextAction == .retryMeasure(source))
    #expect(summary.passageTitle == "第 1 小节")
    #expect(summary.hotspotTitle == "第 1 小节")
}

@Test
func roundSummaryUsesSourceTokensForPassageAndHotspot() throws {
    let start = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 11, sourceNumberToken: "12A")
    let end = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 12, sourceNumberToken: "13")
    let passage = try #require(PracticePassage(
        start: PracticeMeasureOccurrenceID(sourceMeasureID: start, occurrenceIndex: 0),
        end: PracticeMeasureOccurrenceID(sourceMeasureID: end, occurrenceIndex: 1)
    ))
    let configuration = PracticeRoundConfiguration(
        passage: passage,
        handMode: .right,
        tempoScale: 0.6,
        loopEnabled: true,
        requiredSuccesses: 3
    )
    let progress = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "r"),
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: start,
            handMode: .right,
            state: .learning,
            failedAttempts: 1,
            recentIssue: .wrongNote
        )],
        updatedAt: .now
    )
    let summary = try #require(PracticeRoundSummaryViewModel(
        progress: progress,
        configuration: configuration,
        passageSourceMeasureIDs: [start, end],
        isFullPassage: false
    ))
    #expect(summary.passageTitle == "第 12A–13 小节")
    #expect(summary.hotspotTitle == "第 12A 小节")
    #expect(summary.configuration.handMode == .right)
    #expect(summary.configuration.tempoScale == 0.6)
}

@Test
func roundSummaryIgnoresFactsOutsideActivePassage() throws {
    let active = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 1)
    let occurrence = PracticeMeasureOccurrenceID(sourceMeasureID: active, occurrenceIndex: 1)
    let passage = try #require(PracticePassage(start: occurrence, end: occurrence))
    let configuration = PracticeRoundConfiguration(passage: passage, handMode: .both, tempoScale: 0.8, loopEnabled: false, requiredSuccesses: 1)
    let progress = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "r"),
        measureFacts: [
            feedbackFacts(index: 0, failures: 9, issue: .wrongNote),
            feedbackFacts(index: 1, state: .stable),
        ],
        updatedAt: .now
    )
    let summary = try #require(PracticeRoundSummaryViewModel(
        progress: progress,
        configuration: configuration,
        passageSourceMeasureIDs: [active],
        isFullPassage: false
    ))
    #expect(summary.hotspot == nil)
    #expect(summary.isStable)
}

@Test
func roundSummaryRequiresEveryExpectedMeasure() throws {
    let first = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let second = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 1)
    let passage = try #require(PracticePassage(
        start: PracticeMeasureOccurrenceID(sourceMeasureID: first, occurrenceIndex: 0),
        end: PracticeMeasureOccurrenceID(sourceMeasureID: second, occurrenceIndex: 1)
    ))
    let configuration = PracticeRoundConfiguration(
        passage: passage,
        handMode: .both,
        tempoScale: 0.6,
        loopEnabled: true,
        requiredSuccesses: 1
    )
    let progress = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "r"),
        measureFacts: [MeasurePracticeFacts(sourceMeasureID: first, handMode: .both, state: .stable)],
        updatedAt: .now
    )
    let summary = try #require(PracticeRoundSummaryViewModel(
        progress: progress,
        configuration: configuration,
        passageSourceMeasureIDs: [first, second],
        isFullPassage: false
    ))
    #expect(summary.isStable == false)
    #expect(summary.nextAction == .continuePassage)
}
