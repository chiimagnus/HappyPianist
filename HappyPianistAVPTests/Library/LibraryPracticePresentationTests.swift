import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func freshFullScorePresentationUsesCurrentPendingConfiguration() throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = presentationSpans()
    let configuration = PracticeRoundConfiguration(
        passage: try #require(PracticePassage(start: spans[0].occurrenceID, end: spans[2].occurrenceID)),
        handMode: .both,
        tempoScale: 1,
        loopEnabled: false,
        requiredSuccesses: 3
    )

    let presentation = try #require(LibraryPracticePanelPresentation(
        entryID: identity.songID,
        identity: identity,
        measureSpans: spans,
        progress: nil,
        configuration: configuration,
        currentMeasure: spans[0].sourceMeasureID
    ))

    #expect(presentation.passageTitle == "整首")
    #expect(presentation.launchSummary == "整首 · 双手 · 100%")
    #expect(presentation.resumeText == "尚无练习记录")
    #expect(presentation.stableMeasureCount == 0)
    #expect(presentation.totalMeasureCount == 3)
    #expect(presentation.hasSavedProgress == false)
}

@Test
func savedPresentationShowsResumeStableMeasuresAndHotspot() throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = presentationSpans()
    let passage = try #require(PracticePassage(start: spans[0].occurrenceID, end: spans[2].occurrenceID))
    let configuration = PracticeRoundConfiguration(
        passage: passage,
        handMode: .right,
        tempoScale: 0.7,
        loopEnabled: true,
        requiredSuccesses: 3
    )
    let progress = SongPracticeProgress(
        identity: identity,
        activeConfiguration: configuration,
        resumePoint: PracticeResumePoint(
            occurrenceID: spans[1].occurrenceID,
            stepIndex: 1,
            updatedAt: .now
        ),
        measureFacts: [
            MeasurePracticeFacts(
                sourceMeasureID: spans[0].sourceMeasureID,
                handMode: .right,
                state: .stable,
                successfulAttempts: 3,
                consecutiveSuccesses: 3
            ),
            MeasurePracticeFacts(
                sourceMeasureID: spans[1].sourceMeasureID,
                handMode: .right,
                state: .learning,
                failedAttempts: 2,
                recentIssue: .wrongNote,
                lastAttemptAt: .now
            ),
        ],
        updatedAt: .now
    )

    let presentation = try #require(LibraryPracticePanelPresentation(
        entryID: identity.songID,
        identity: identity,
        measureSpans: spans,
        progress: progress,
        configuration: configuration,
        currentMeasure: spans[1].sourceMeasureID
    ))

    #expect(presentation.resumeText == "将从第 2 小节继续")
    #expect(presentation.stableMeasureCount == 1)
    #expect(presentation.hotspotTitle == "第 2 小节")
    #expect(presentation.hasSavedProgress)
    #expect(presentation.measureMap.items.first(where: { $0.id == spans[1].sourceMeasureID })?.isHotspot == true)
}

@Test
func repeatedMeasurePresentationUsesOccurrenceOrderAndUniqueMeasureCount() throws {
    let spans = repeatedPresentationSpans()
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let configuration = PracticeRoundConfiguration(
        passage: try #require(PracticePassage(start: spans[1].occurrenceID, end: spans[2].occurrenceID)),
        handMode: .both,
        tempoScale: 0.9,
        loopEnabled: false,
        requiredSuccesses: 3
    )

    let presentation = try #require(LibraryPracticePanelPresentation(
        entryID: identity.songID,
        identity: identity,
        measureSpans: spans,
        progress: nil,
        configuration: configuration,
        currentMeasure: nil
    ))

    #expect(presentation.passageTitle == "第 2 小节至重复后的第 1 小节")
    #expect(presentation.totalMeasureCount == 2)
    #expect(presentation.measureMap.items.count == 2)
}

@Test
func mismatchedProgressIdentityIsIgnored() throws {
    let currentIdentity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r2")
    let staleIdentity = PracticeSongIdentity(songID: currentIdentity.songID, scoreRevision: "r1")
    let spans = presentationSpans()
    let configuration = PracticeRoundConfiguration(
        passage: try #require(PracticePassage(start: spans[0].occurrenceID, end: spans[2].occurrenceID)),
        handMode: .both,
        tempoScale: 1,
        loopEnabled: false,
        requiredSuccesses: 3
    )
    let staleProgress = SongPracticeProgress(
        identity: staleIdentity,
        activeConfiguration: configuration,
        resumePoint: PracticeResumePoint(
            occurrenceID: spans[2].occurrenceID,
            stepIndex: 2,
            updatedAt: .now
        ),
        measureFacts: [
            MeasurePracticeFacts(
                sourceMeasureID: spans[0].sourceMeasureID,
                handMode: .both,
                state: .stable,
                successfulAttempts: 3,
                consecutiveSuccesses: 3
            )
        ],
        updatedAt: .now
    )

    let presentation = try #require(LibraryPracticePanelPresentation(
        entryID: currentIdentity.songID,
        identity: currentIdentity,
        measureSpans: spans,
        progress: staleProgress,
        configuration: configuration,
        currentMeasure: spans[0].sourceMeasureID
    ))

    #expect(presentation.resumeText == "尚无练习记录")
    #expect(presentation.stableMeasureCount == 0)
    #expect(presentation.hasSavedProgress == false)
}

private func presentationSpans() -> [MusicXMLMeasureSpan] {
    [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 0, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 1, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 3, sourceMeasureIndex: 2, sourceMeasureNumberToken: "3", occurrenceIndex: 2, startTick: 960, endTick: 1_440),
    ]
}

private func repeatedPresentationSpans() -> [MusicXMLMeasureSpan] {
    [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 0, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 1, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 0, sourceMeasureNumberToken: "1", occurrenceIndex: 2, startTick: 960, endTick: 1_440),
    ]
}
