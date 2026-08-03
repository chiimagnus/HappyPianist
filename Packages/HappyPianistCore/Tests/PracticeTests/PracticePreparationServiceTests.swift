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
func preparationKeepsAllFourteenStandardWrittenRhythms() async throws {
    let url = try writePreparationFixture(named: "fourteen-rhythms", contents: fourteenRhythmFixture)
    defer { try? FileManager.default.removeItem(at: url) }

    let prepared = try await PracticePreparationService(
        diagnosticsReporter: PreparationDiagnosticsReporter()
    ).prepare(
        songID: UUID(),
        from: url,
        file: ImportedMusicXMLFile(fileName: "Fourteen Rhythms", storedURL: url, importedAt: .now),
        options: .practice
    )

    #expect(prepared.scoreContext.sourceScore.notes.compactMap { $0.writtenRhythm?.noteType } == MusicXMLNoteType.allCases)
    #expect(prepared.scoreContext.sourceScore.notes.first?.durationTicks == 15)
    #expect(prepared.steps.count == MusicXMLNoteType.allCases.count)
}

@Test
func preparationMapsInvalidWrittenRhythmToTypedFailure() async throws {
    let invalidFixture = preparationFixture.replacing("<type>quarter</type>", with: "")
    let url = try writePreparationFixture(named: "missing-rhythm", contents: invalidFixture)
    defer { try? FileManager.default.removeItem(at: url) }

    await #expect(throws: PracticePreparationError.invalidWrittenRhythm(.missingType)) {
        _ = try await PracticePreparationService(
            diagnosticsReporter: PreparationDiagnosticsReporter()
        ).prepare(
            songID: UUID(),
            from: url,
            file: ImportedMusicXMLFile(fileName: "Missing Rhythm", storedURL: url, importedAt: .now),
            options: .practice
        )
    }
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

private func writePreparationFixture(named name: String, contents: String = preparationFixture) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString).musicxml")
    try Data(contents.utf8).write(to: url)
    return url
}

private let fourteenRhythmFixture = """
<score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
<part id="P1"><measure number="1"><attributes><divisions>256</divisions></attributes>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>1024th</type></note>
<note><pitch><step>D</step><octave>4</octave></pitch><duration>2</duration><type>512th</type></note>
<note><pitch><step>E</step><octave>4</octave></pitch><duration>4</duration><type>256th</type></note>
<note><pitch><step>F</step><octave>4</octave></pitch><duration>8</duration><type>128th</type></note>
<note><pitch><step>G</step><octave>4</octave></pitch><duration>16</duration><type>64th</type></note>
<note><pitch><step>A</step><octave>4</octave></pitch><duration>32</duration><type>32nd</type></note>
<note><pitch><step>B</step><octave>4</octave></pitch><duration>64</duration><type>16th</type></note>
<note><pitch><step>C</step><octave>5</octave></pitch><duration>128</duration><type>eighth</type></note>
<note><pitch><step>D</step><octave>5</octave></pitch><duration>256</duration><type>quarter</type></note>
<note><pitch><step>E</step><octave>5</octave></pitch><duration>512</duration><type>half</type></note>
<note><pitch><step>F</step><octave>5</octave></pitch><duration>1024</duration><type>whole</type></note>
<note><pitch><step>G</step><octave>5</octave></pitch><duration>2048</duration><type>breve</type></note>
<note><pitch><step>A</step><octave>5</octave></pitch><duration>4096</duration><type>long</type></note>
<note><pitch><step>B</step><octave>5</octave></pitch><duration>8192</duration><type>maxima</type></note>
</measure></part></score-partwise>
"""

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
