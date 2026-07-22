import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func positiveFeedbackFactsDriveCueSummaryRetryAndRestoredMap() throws {
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0, sourceNumberToken: "1")
    let occurrence = PracticeMeasureOccurrenceID(sourceMeasureID: source, occurrenceIndex: 0)
    let passage = try #require(PracticePassage(start: occurrence, end: occurrence))
    let configuration = PracticeRoundConfiguration(passage: passage, handMode: .both, tempoScale: 0.8, loopEnabled: false, requiredSuccesses: 1)
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r")
    let facts = MeasurePracticeFacts(
        sourceMeasureID: source,
        handMode: .both,
        state: .learning,
        failedAttempts: 1,
        recentIssue: .wrongNote
    )
    let progress = SongPracticeProgress(identity: identity, activeConfiguration: configuration, measureFacts: [facts], updatedAt: .now)
    let decision = feedbackDecision(source: source)

    let hotspot = try #require(PracticeHotspotPolicy().hotspot(for: decision))
    let summary = try #require(PracticeRoundSummaryViewModel(
        progress: progress,
        configuration: configuration,
        passageOccurrences: [occurrence],
        isFullPassage: true,
        coachingDecision: decision
    ))
    let span = MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 0, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480)
    let restoredMap = PracticeMeasureMapViewModel(measureSpans: [span], progress: progress, handMode: .both, currentPassage: passage, currentMeasure: source, coachingDecision: decision)

    #expect(hotspot.sourceMeasureID == source)
    #expect(summary.nextAction == .retryMeasure(source))
    #expect(restoredMap.items == [PracticeMeasureMapItem(id: source, displayNumber: "1", state: .learning, isCurrentPassage: true, isCurrentMeasure: true, isHotspot: true)])
}
