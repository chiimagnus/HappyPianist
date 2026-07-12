import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func diagnosticFileReferenceRejectsAbsoluteAndTraversalPaths() {
    #expect(DiagnosticFileReference(fileName: "score.musicxml", relativePath: "/Users/test/score.musicxml") == nil)
    #expect(DiagnosticFileReference(fileName: "score.musicxml", relativePath: "SongLibrary/../score.musicxml") == nil)
    #expect(DiagnosticFileReference(fileName: "score.musicxml", relativePath: "file://score.musicxml") == nil)
}

@Test
func diagnosticFileReferenceNormalizesSafeRelativePath() throws {
    let reference = try #require(
        DiagnosticFileReference(
            fileName: "/tmp/example.musicxml",
            relativePath: "SongLibrary\\scores\\example.musicxml"
        )
    )
    #expect(reference.fileName == "example.musicxml")
    #expect(reference.relativePath == "SongLibrary/scores/example.musicxml")
}

@Test
func diagnosticEventTextRepresentationContainsStableFields() throws {
    let reference = try #require(
        DiagnosticFileReference(
            fileName: "example.musicxml",
            relativePath: "SongLibrary/scores/example.musicxml"
        )
    )
    let eventID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let event = DiagnosticEvent(
        id: eventID,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        severity: .error,
        code: .practiceXMLParseFailed,
        category: .practicePreparation,
        stage: "musicXMLParsing",
        summary: "无法解析 MusicXML",
        reason: "Opening and ending tag mismatch",
        songID: UUID(uuidString: "00000000-0000-0000-0000-000000000002"),
        file: reference,
        sourceLocation: DiagnosticSourceLocation(line: 42, column: 7),
        persistence: .exportable
    )

    let text = event.textRepresentation
    #expect(text.contains("code: PRACTICE_XML_PARSE_FAILED"))
    #expect(text.contains("relativePath: SongLibrary/scores/example.musicxml"))
    #expect(text.contains("line: 42"))
    #expect(text.contains("column: 7"))
    #expect(text.contains("/Users/") == false)
}

@Test
func diagnosticEventCodableRoundTrips() throws {
    let event = DiagnosticEvent(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        severity: .warning,
        code: .diagnosticsStoreWriteFailed,
        category: .diagnostics,
        stage: "append",
        summary: "写入失败",
        reason: "disk full",
        persistence: .systemOnly
    )

    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(DiagnosticEvent.self, from: data)
    #expect(decoded == event)
}
