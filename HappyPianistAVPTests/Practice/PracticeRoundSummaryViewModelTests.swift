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
    let summary = try #require(PracticeRoundSummaryViewModel(progress: progress, configuration: configuration, isFullPassage: true))
    #expect(summary.hotspot?.sourceMeasureID == source)
    #expect(summary.nextAction == .retryMeasure(source))
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
    let summary = try #require(PracticeRoundSummaryViewModel(progress: progress, configuration: configuration, isFullPassage: false))
    #expect(summary.hotspot == nil)
    #expect(summary.isStable)
}
