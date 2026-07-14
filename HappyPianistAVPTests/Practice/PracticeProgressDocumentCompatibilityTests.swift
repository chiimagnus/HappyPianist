import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func progressDocumentDecodesLegacySongsOnlyAndUnknownKeys() throws {
    let json = """
    {
      "songs": [],
      "futureField": { "ignored": true }
    }
    """
    let decoder = JSONDecoder()

    let document = try decoder.decode(PracticeProgressDocument.self, from: Data(json.utf8))

    #expect(document == PracticeProgressDocument())
}

@Test
func progressDocumentDecodesMissingArraysAsEmpty() throws {
    let document = try JSONDecoder().decode(
        PracticeProgressDocument.self,
        from: Data("{}".utf8)
    )

    #expect(document.songs.isEmpty)
    #expect(document.scoreMetadata.isEmpty)
}

@Test
func progressDocumentRoundTripsMetadataIncludingNilAndNonNilTokens() throws {
    let songID = UUID()
    let document = PracticeProgressDocument(scoreMetadata: [
        SongScorePracticeMetadata(
            songID: songID,
            scoreFileVersionID: nil,
            scoreRevision: "legacy",
            totalSourceMeasureCount: -1,
            preparedAt: Date(timeIntervalSince1970: 10)
        ),
        SongScorePracticeMetadata(
            songID: songID,
            scoreFileVersionID: UUID(),
            scoreRevision: "current",
            totalSourceMeasureCount: 12,
            preparedAt: Date(timeIntervalSince1970: 20)
        ),
    ])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let decoded = try decoder.decode(
        PracticeProgressDocument.self,
        from: encoder.encode(document)
    )

    #expect(decoded == document)
    #expect(decoded.scoreMetadata.first?.totalSourceMeasureCount == 0)
}

@Test
func duplicateProgressTieBreakDoesNotDependOnDocumentOrder() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let date = Date(timeIntervalSince1970: 100)
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let first = SongPracticeProgress(
        identity: identity,
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: source,
            handMode: .right,
            successfulAttempts: 1,
            lastAttemptAt: date
        )],
        updatedAt: date
    )
    let second = SongPracticeProgress(
        identity: identity,
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: source,
            handMode: .right,
            failedAttempts: 1,
            lastAttemptAt: date
        )],
        updatedAt: date
    )

    #expect(
        PracticeProgressRecordOrder.preferred(in: [first, second])
            == PracticeProgressRecordOrder.preferred(in: [second, first])
    )
}

@Test
func duplicateProgressTieBreakPreservesNestedDateFractions() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let updatedAt = Date(timeIntervalSince1970: 100)
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let first = SongPracticeProgress(
        identity: identity,
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: source,
            handMode: .right,
            failedAttempts: 1,
            lastAttemptAt: Date(timeIntervalSince1970: 100.1)
        )],
        updatedAt: updatedAt
    )
    let second = SongPracticeProgress(
        identity: identity,
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: source,
            handMode: .right,
            failedAttempts: 1,
            lastAttemptAt: Date(timeIntervalSince1970: 100.2)
        )],
        updatedAt: updatedAt
    )

    #expect(
        PracticeProgressRecordOrder.preferred(in: [first, second])
            == PracticeProgressRecordOrder.preferred(in: [second, first])
    )
}
