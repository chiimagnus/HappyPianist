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
func practiceProgressDocumentSuppliesMigrationDefaults() throws {
    let decoded = try JSONDecoder().decode(
        PracticeProgressDocument.self,
        from: Data("{}".utf8)
    )

    #expect(decoded.schemaVersion == PracticeProgressDocument.currentSchemaVersion)
    #expect(decoded.songs.isEmpty)
}

@Test
func nestedProgressModelsSupplyMigrationDefaults() throws {
    let songID = UUID()
    let json = """
    {
      "songs": [{
        "identity": { "songID": "\(songID.uuidString)", "scoreRevision": "r1" },
        "activeConfiguration": {
          "passage": {
            "start": { "sourceMeasureID": { "partID": "P1", "sourceMeasureIndex": 0 }, "occurrenceIndex": 0 },
            "end": { "sourceMeasureID": { "partID": "P1", "sourceMeasureIndex": 0 }, "occurrenceIndex": 0 }
          }
        },
        "resumePoint": {
          "occurrenceID": { "sourceMeasureID": { "partID": "P1", "sourceMeasureIndex": 0 }, "occurrenceIndex": 0 }
        },
        "measureFacts": [{
          "sourceMeasureID": { "partID": "P1", "sourceMeasureIndex": 0 }
        }]
      }]
    }
    """

    let document = try JSONDecoder().decode(PracticeProgressDocument.self, from: Data(json.utf8))
    let progress = try #require(document.songs.first)
    let configuration = try #require(progress.activeConfiguration)
    let facts = try #require(progress.measureFacts.first)

    #expect(configuration.handMode == .both)
    #expect(configuration.tempoScale == 1)
    #expect(configuration.loopEnabled == false)
    #expect(configuration.requiredSuccesses == 3)
    #expect(progress.resumePoint?.stepIndex == 0)
    #expect(progress.updatedAt == .distantPast)
    #expect(facts.state == .notStarted)
    #expect(facts.successfulAttempts == 0)
    #expect(facts.failedAttempts == 0)
    #expect(facts.consecutiveSuccesses == 0)
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
