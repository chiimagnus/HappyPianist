import Diagnostics
import Foundation
@testable import MusicXML
@testable import Practice
import Testing

private let preparationFixture = """
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes><note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note><barline location="right"><repeat direction="backward"/></barline></measure></part>
</score-partwise>
"""

@Test
func preparationKeepsSongIdentityAndChangesRevisionWithScoreBytes() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appending(path: "score.musicxml")
    try Data(preparationFixture.utf8).write(to: url)
    let songID = UUID()
    let file = ImportedMusicXMLFile(fileName: "Fixture", storedURL: url, importedAt: .now)
    let service = PracticePreparationService(diagnosticsReporter: PreparationDiagnosticsReporter())

    let first = try await service.prepare(songID: songID, from: url, file: file, options: .practice)
    let second = try await service.prepare(songID: songID, from: url, file: file, options: .practice)

    #expect(first.identity.songID == songID)
    #expect(first.identity.scoreRevision == second.identity.scoreRevision)
    #expect(first.steps.isEmpty == false)
    #expect(first.measureSpans.isEmpty == false)

    try Data(preparationFixture.replacing("<step>C</step>", with: "<step>D</step>").utf8).write(to: url)
    let replaced = try await service.prepare(songID: songID, from: url, file: file, options: .practice)
    #expect(replaced.identity.scoreRevision != first.identity.scoreRevision)
}

@Test
func cancelledPreparationDoesNotProducePreparedPractice() async throws {
    let url = try writePreparationFixture(named: "cancelled")
    defer { try? FileManager.default.removeItem(at: url) }

    let task = Task {
        try await PracticePreparationService(diagnosticsReporter: PreparationDiagnosticsReporter()).prepare(
            songID: UUID(),
            from: url,
            file: ImportedMusicXMLFile(fileName: "Cancelled", storedURL: url, importedAt: .now),
            options: .practice
        )
    }
    task.cancel()

    await #expect(throws: CancellationError.self) {
        _ = try await task.value
    }
}

@Test
func preparationRejectsEmptyStepProjection() async throws {
    let url = try writePreparationFixture(named: "empty-steps")
    defer { try? FileManager.default.removeItem(at: url) }

    let service = PracticePreparationService(
        diagnosticsReporter: PreparationDiagnosticsReporter(),
        stepBuilder: EmptyStepBuilder()
    )

    await #expect(throws: PracticePreparationError.noPlayableNotes) {
        _ = try await service.prepare(
            songID: UUID(),
            from: url,
            file: ImportedMusicXMLFile(fileName: "Empty Steps", storedURL: url, importedAt: .now),
            options: .practice
        )
    }
}

@Test
func preparationRejectsMissingMeasureStructure() async throws {
    let url = try writePreparationFixture(named: "missing-measures")
    defer { try? FileManager.default.removeItem(at: url) }

    let service = PracticePreparationService(
        diagnosticsReporter: PreparationDiagnosticsReporter(),
        parser: MissingMeasureParser()
    )

    await #expect(throws: PracticePreparationError.missingMeasureStructure) {
        _ = try await service.prepare(
            songID: UUID(),
            from: url,
            file: ImportedMusicXMLFile(fileName: "Missing Measures", storedURL: url, importedAt: .now),
            options: .practice
        )
    }
}

private func writePreparationFixture(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString).musicxml")
    try Data(preparationFixture.utf8).write(to: url)
    return url
}

private struct EmptyStepBuilder: PracticeStepBuilderProtocol {
    func buildSteps(from _: ScorePerformancePlan) -> PracticeStepBuildResult {
        PracticeStepBuildResult(steps: [], unsupportedNoteCount: 0)
    }
}

private struct MissingMeasureParser: MusicXMLParserProtocol {
    func parse(data: Data) throws -> MusicXMLScore {
        var score = try MusicXMLParser().parse(data: data)
        score.measures = []
        return score
    }

    func parse(fileURL: URL) throws -> MusicXMLScore {
        try parse(data: Data(contentsOf: fileURL))
    }
}

private actor PreparationDiagnosticsReporter: DiagnosticsReporting {
    func record(_ event: DiagnosticEvent) -> DiagnosticRecordResult {
        DiagnosticRecordResult(persistedForExport: false)
    }
}
