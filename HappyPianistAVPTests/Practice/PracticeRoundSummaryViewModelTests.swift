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
        passageOccurrences: [occurrence],
        isFullPassage: true,
        coachingDecision: feedbackDecision(source: source)
    ))
    #expect(summary.hotspot?.sourceMeasureID == source)
    #expect(summary.nextAction == .retryMeasure(source))
    #expect(summary.passageTitle == "第 1 小节")
    #expect(summary.hotspotTitle == "第 1 小节")
    #expect(summary.detailText.contains("练习片段：第 1 小节"))
    #expect(summary.detailText.contains("练习手：\(configuration.handMode.title)"))
    #expect(summary.detailText.contains("速度：80%"))
    #expect(summary.detailText.contains("可以再照顾第 1 小节"))
    #expect(summary.detailText.contains("下一步：确认音高后重练"))
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
        passageOccurrences: [
            PracticeMeasureOccurrenceID(sourceMeasureID: start, occurrenceIndex: 0),
            PracticeMeasureOccurrenceID(sourceMeasureID: end, occurrenceIndex: 1),
        ],
        isFullPassage: false,
        coachingDecision: feedbackDecision(source: start)
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
            feedbackFacts(index: 1, state: .pitchStepStable),
        ],
        updatedAt: .now
    )
    let summary = try #require(PracticeRoundSummaryViewModel(
        progress: progress,
        configuration: configuration,
        passageOccurrences: [occurrence],
        isFullPassage: false
    ))
    #expect(summary.hotspot == nil)
    #expect(summary.hasStablePitchSteps)
    #expect(summary.detailText.contains("可以再照顾") == false)
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
        measureFacts: [MeasurePracticeFacts(sourceMeasureID: first, handMode: .both, state: .pitchStepStable)],
        updatedAt: .now
    )
    let summary = try #require(PracticeRoundSummaryViewModel(
        progress: progress,
        configuration: configuration,
        passageOccurrences: [
            PracticeMeasureOccurrenceID(sourceMeasureID: first, occurrenceIndex: 0),
            PracticeMeasureOccurrenceID(sourceMeasureID: second, occurrenceIndex: 1),
        ],
        isFullPassage: false
    ))
    #expect(summary.hasStablePitchSteps == false)
    #expect(summary.nextAction == .continuePassage)
}

@Test
func roundSummaryDescribesRepeatBoundaryInPlaybackOrder() throws {
    let seventh = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 6, sourceNumberToken: "7")
    let first = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0, sourceNumberToken: "1")
    let occurrences = [
        PracticeMeasureOccurrenceID(sourceMeasureID: seventh, occurrenceIndex: 6),
        PracticeMeasureOccurrenceID(sourceMeasureID: first, occurrenceIndex: 7),
    ]
    let passage = try #require(PracticePassage(start: occurrences[0], end: occurrences[1]))
    let configuration = PracticeRoundConfiguration(
        passage: passage,
        handMode: .both,
        tempoScale: 0.6,
        loopEnabled: true,
        requiredSuccesses: 3
    )
    let summary = try #require(PracticeRoundSummaryViewModel(
        progress: SongPracticeProgress(
            identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "r"),
            updatedAt: .now
        ),
        configuration: configuration,
        passageOccurrences: occurrences,
        isFullPassage: false
    ))
    #expect(summary.passageTitle == "第 7 小节至重复后的第 1 小节")
}
