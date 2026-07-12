import Foundation
@testable import HappyPianistAVP
import Testing

private func makeOccurrence(_ index: Int, partID: String = "P1") -> PracticeMeasureOccurrenceID {
    PracticeMeasureOccurrenceID(
        sourceMeasureID: PracticeSourceMeasureID(
            partID: partID,
            sourceMeasureIndex: index,
            sourceNumberToken: String(index + 1)
        ),
        occurrenceIndex: index
    )
}

@Test
func practiceProgressDocumentRoundTrips() throws {
    let passage = try #require(PracticePassage(start: makeOccurrence(1), end: makeOccurrence(4)))
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "sha256:abc")
    let date = Date(timeIntervalSince1970: 1_234)
    let configuration = PracticeRoundConfiguration(
        passage: passage,
        handMode: .right,
        tempoScale: 0.6,
        loopEnabled: true,
        requiredSuccesses: 3
    )
    let document = PracticeProgressDocument(songs: [
        SongPracticeProgress(
            identity: identity,
            activeConfiguration: configuration,
            resumePoint: PracticeResumePoint(occurrenceID: makeOccurrence(2), stepIndex: 7, updatedAt: date),
            measureFacts: [
                MeasurePracticeFacts(
                    sourceMeasureID: makeOccurrence(2).sourceMeasureID,
                    handMode: .right,
                    state: .learning,
                    successfulAttempts: 2,
                    failedAttempts: 1,
                    consecutiveSuccesses: 2,
                    recentIssue: .incompleteChord,
                    lastAttemptAt: date
                )
            ],
            updatedAt: date
        )
    ])

    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(PracticeProgressDocument.self, from: data)

    #expect(decoded == document)
}

@Test
func practiceProgressDocumentRejectsMissingRequiredFields() {
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(
            PracticeProgressDocument.self,
            from: Data("{}".utf8)
        )
    }
}

@Test
func roundConfigurationClampsSupportedValues() throws {
    let passage = try #require(PracticePassage(start: makeOccurrence(0), end: makeOccurrence(0)))
    let low = PracticeRoundConfiguration(
        passage: passage,
        handMode: .both,
        tempoScale: 0.1,
        loopEnabled: false,
        requiredSuccesses: 0
    )
    let high = PracticeRoundConfiguration(
        passage: passage,
        handMode: .both,
        tempoScale: 2,
        loopEnabled: false,
        requiredSuccesses: 99
    )

    #expect(low.tempoScale == 0.5)
    #expect(low.requiredSuccesses == 1)
    #expect(high.tempoScale == 1.0)
    #expect(high.requiredSuccesses == 5)
}

@Test
func passageRejectsInvalidOrderOrMixedParts() {
    #expect(PracticePassage(start: makeOccurrence(4), end: makeOccurrence(2)) == nil)
    #expect(PracticePassage(start: makeOccurrence(1, partID: "P1"), end: makeOccurrence(2, partID: "P2")) == nil)
}

@Test
func identityUsesSongAndRevision() {
    let songID = UUID()
    #expect(
        PracticeSongIdentity(songID: songID, scoreRevision: "a")
            != PracticeSongIdentity(songID: songID, scoreRevision: "b")
    )
}
