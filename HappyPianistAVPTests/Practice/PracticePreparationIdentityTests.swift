import Foundation
@testable import HappyPianistAVP
import os
import Testing

private let identityFixtureA = """
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes><note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note></measure></part>
</score-partwise>
"""

private let identityFixtureB = identityFixtureA.replacing("<step>C</step>", with: "<step>D</step>")

private let identityRepeatFixture = """
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>1</divisions></attributes>
      <barline location="left"><repeat direction="forward"/></barline>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
    </measure>
    <measure number="2">
      <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration></note>
      <barline location="right"><repeat direction="backward"/></barline>
    </measure>
  </part>
</score-partwise>
"""

private let identityDaCapoFixture = """
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>1</divisions></attributes>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
      <direction><sound dacapo="yes"/></direction>
    </measure>
  </part>
</score-partwise>
"""

@Test
func preparationKeepsExactSongIDAndStableRevision() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appending(path: "score.musicxml")
    try Data(identityFixtureA.utf8).write(to: url)
    let songID = UUID()
    let file = ImportedMusicXMLFile(fileName: "Fixture", storedURL: url, importedAt: .now)
    let service = PracticePreparationService(diagnosticsReporter: InMemoryDiagnosticsReporter())

    let first = try await service.prepare(songID: songID, from: url, file: file)
    let second = try await service.prepare(songID: songID, from: url, file: file)

    #expect(first.identity.songID == songID)
    #expect(first.identity.scoreRevision == second.identity.scoreRevision)
    #expect(first.scoreContext.logicalInstrument.classification == .piano)
    #expect(first.scoreContext.logicalInstrument.memberPartIDs == ["P1"])
    #expect(first.scoreContext.structuralPartID == "P1")
    #expect(first.scoreContext.orderSelection == MusicXMLOrderSelection(requested: .written, applied: .written))
    #expect(first.scoreContext.sourceScore == first.scoreContext.preparedScore)
    #expect(first.scoreContext.sourceScore.notes.first?.sourceID != nil)
    #expect(first.performancePlan.sourceScoreIdentity == ScorePerformanceSourceIdentity(
        songID: songID,
        scoreRevision: first.identity.scoreRevision,
        logicalInstrumentID: first.scoreContext.logicalInstrument.id
    ))
    #expect(first.performancePlan.noteEvents.map(\.midiNote) == [60])

    try Data(identityFixtureB.utf8).write(to: url)
    let replaced = try await service.prepare(songID: songID, from: url, file: file)
    #expect(replaced.identity.scoreRevision != first.identity.scoreRevision)
}

@Test
func referencePlaybackPreparationExpandsPerformedOrderWithoutLosingSourceIdentity() async throws {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "performed-order-\(UUID().uuidString).musicxml"
    )
    try Data(identityRepeatFixture.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let service = PracticePreparationService(diagnosticsReporter: InMemoryDiagnosticsReporter())
    let prepared = try await service.prepare(
        songID: UUID(),
        from: url,
        file: ImportedMusicXMLFile(fileName: "Repeat", storedURL: url, importedAt: .now),
        options: .referencePlayback
    )

    #expect(prepared.scoreContext.orderSelection == MusicXMLOrderSelection(requested: .performed, applied: .performed))
    #expect(prepared.scoreContext.sourceScore.notes.compactMap(\.midiNote) == [60, 62])
    #expect(prepared.scoreContext.preparedScore.notes.compactMap(\.midiNote) == [60, 62, 60, 62])
    #expect(Set(prepared.scoreContext.preparedScore.notes.compactMap(\.sourceID)).count == 2)
    #expect(Set(prepared.scoreContext.preparedScore.notes.compactMap(\.performedID)).count == 4)
    #expect(prepared.measureSpans.map(\.occurrenceIndex) == [0, 1, 2, 3])
    #expect(prepared.performancePlan.order == prepared.scoreContext.orderSelection)
    #expect(prepared.performancePlan.noteEvents.map(\.midiNote) == [60, 62, 60, 62])
}

@Test
func referencePlaybackPreparationReportsWrittenFallbackWhenExpansionLimitIsHit() async throws {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "performed-order-limit-\(UUID().uuidString).musicxml"
    )
    try Data(identityDaCapoFixture.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let service = PracticePreparationService(
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        structureExpander: MusicXMLStructureExpander(maxOutputMeasures: 0)
    )
    let prepared = try await service.prepare(
        songID: UUID(),
        from: url,
        file: ImportedMusicXMLFile(fileName: "Da Capo", storedURL: url, importedAt: .now),
        options: .referencePlayback
    )

    #expect(prepared.scoreContext.orderSelection == MusicXMLOrderSelection(
        requested: .performed,
        applied: .written,
        approximationReason: "structure-expansion-output-measure-limit"
    ))
    #expect(prepared.scoreContext.preparedScore == prepared.scoreContext.sourceScore)
}

@Test
func splitPianoPreparationUsesThePartThatOwnsStructureDirectives() async throws {
    let url = testFixtureURL("SplitPartGrandStaffPiano.musicxml")
    let prepared = try await PracticePreparationService(
        diagnosticsReporter: InMemoryDiagnosticsReporter()
    ).prepare(
        songID: UUID(),
        from: url,
        file: ImportedMusicXMLFile(fileName: "Split Piano", storedURL: url, importedAt: .now),
        options: .referencePlayback
    )

    #expect(prepared.scoreContext.logicalInstrument.memberPartIDs == ["LH", "RH"])
    #expect(prepared.scoreContext.structuralPartID == "RH")
    #expect(prepared.scoreContext.preparedScore.notes.count == 8)
    #expect(Set(prepared.scoreContext.preparedScore.notes.map(\.partID)) == ["LH", "RH"])
    #expect(prepared.measureSpans.map(\.occurrenceIndex) == [0, 1, 2, 3])
}

@Test
func underPressureSeedScorePreparesAndProjectsBothGrandStaffParts() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let directoryName = "Under_Pressure_-_David_Bowie,_David_Bowie_&_Queen,_Queen_(Piano_Solo)"
    let url = repositoryRoot
        .appending(path: "HappyPianistAVP/Resources/SeedScores")
        .appending(path: directoryName)
        .appending(path: "\(directoryName).musicxml")
    let prepared = try await PracticePreparationService(
        diagnosticsReporter: InMemoryDiagnosticsReporter()
    ).prepare(
        songID: UUID(),
        from: url,
        file: ImportedMusicXMLFile(fileName: url.lastPathComponent, storedURL: url, importedAt: .now)
    )

    #expect(prepared.scoreContext.logicalInstrument.memberPartIDs == [
        "P36df1496bb2f1e2a36c8f68a99ab1838",
        "Pc07d9683d7dd1310ce32aaf3db237f1b",
    ])
    #expect(prepared.scoreContext.logicalInstrument.evidence.contains {
        $0.kind == .complementarySingleStaffClefs
    })
    #expect(Set(prepared.notationProjection.sourceNotes.map(\.staff)) == [1, 2])
    #expect(prepared.steps.isEmpty == false)
    #expect(prepared.measureSpans.isEmpty == false)
}

@Test
func plainMusicXMLPreparationParsesTheAlreadyReadBytes() async throws {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "single-read-\(UUID().uuidString).musicxml"
    )
    let scoreBytes = Data(identityFixtureA.utf8)
    try scoreBytes.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let parser = RecordingPreparationParser()
    let service = PracticePreparationService(
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        parser: parser
    )

    _ = try await service.prepare(
        songID: UUID(),
        from: url,
        file: ImportedMusicXMLFile(fileName: "Single Read", storedURL: url, importedAt: .now)
    )

    #expect(parser.calls == [.data(scoreBytes)])
}

@Test
func compressedMusicXMLPreparationKeepsTheArchiveParserPath() async throws {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "archive-routing-\(UUID().uuidString).mxl"
    )
    try Data("archive-placeholder".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let parser = RecordingPreparationParser()
    let service = PracticePreparationService(
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        parser: parser
    )

    _ = try await service.prepare(
        songID: UUID(),
        from: url,
        file: ImportedMusicXMLFile(fileName: "Archive", storedURL: url, importedAt: .now)
    )

    #expect(parser.calls == [.fileURL(url)])
}

@Test
func preparationRecordsSystemOnlyPlanBuildMetrics() async throws {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "plan-diagnostics-\(UUID().uuidString).musicxml"
    )
    try Data(identityFixtureA.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let songID = UUID()
    let reporter = InMemoryDiagnosticsReporter()
    let service = PracticePreparationService(diagnosticsReporter: reporter)

    _ = try await service.prepare(
        songID: songID,
        from: url,
        file: ImportedMusicXMLFile(fileName: "Diagnostics", storedURL: url, importedAt: .now)
    )

    let events = await reporter.events
    let event = try #require(events.first)
    #expect(events.count == 1)
    #expect(event.code == .pianoPerformancePipeline)
    #expect(event.category == .pianoPerformance)
    #expect(event.stage == PianoPerformanceDiagnosticStage.plan.rawValue)
    #expect(event.severity == .info)
    #expect(event.songID == songID)
    #expect(event.scoreRevision != nil)
    #expect(event.persistence == .systemOnly)
    #expect(event.reason.contains("outcome=succeeded"))
    #expect(event.reason.contains("duration="))
    #expect(event.reason.contains("noteEvents=1"))
    #expect(event.reason.contains("tempoEvents="))
    #expect(event.reason.contains("controllerEvents="))
    #expect(event.reason.contains("annotations="))
    #expect(event.reason.contains("unsupportedNotes=0"))
    #expect(event.reason.contains("approximations=0"))
    #expect(event.reason.contains("stepMismatches=0"))
    #expect(event.reason.contains("highlightMismatches=0"))
    #expect(event.reason.contains("notationMismatches=0"))
    #expect(event.reason.contains(url.path) == false)
    #expect(event.reason.contains("musicxml") == false)
}

@Test
func preparationReportsProjectionMismatchBeforeRejectingEmptySteps() async throws {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "plan-mismatch-\(UUID().uuidString).musicxml"
    )
    try Data(identityFixtureA.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let reporter = InMemoryDiagnosticsReporter()
    let service = PracticePreparationService(
        diagnosticsReporter: reporter,
        stepBuilder: EmptyPreparationStepBuilder()
    )

    await #expect(throws: PracticePreparationError.noPlayableNotes) {
        _ = try await service.prepare(
            songID: UUID(),
            from: url,
            file: ImportedMusicXMLFile(fileName: "Mismatch", storedURL: url, importedAt: .now)
        )
    }

    let events = await reporter.events
    let event = try #require(events.first)
    #expect(events.count == 1)
    #expect(event.severity == .warning)
    #expect(event.persistence == .systemOnly)
    #expect(event.reason.contains("outcome=mismatch"))
    #expect(event.reason.contains("unsupportedNotes=3"))
    #expect(event.reason.contains("stepMismatches=1"))
    #expect(event.reason.contains("highlightMismatches=0"))
    #expect(event.reason.contains("notationMismatches=0"))
}

private struct EmptyPreparationStepBuilder: PracticeStepBuilderProtocol {
    func buildSteps(from _: ScorePerformancePlan) -> PracticeStepBuildResult {
        PracticeStepBuildResult(steps: [], unsupportedNoteCount: 3)
    }
}

private final class RecordingPreparationParser: MusicXMLParserProtocol, Sendable {
    enum Call: Equatable {
        case data(Data)
        case fileURL(URL)
    }

    private let callsLock = OSAllocatedUnfairLock(initialState: [Call]())

    var calls: [Call] {
        callsLock.withLock { $0 }
    }

    func parse(data: Data) throws -> MusicXMLScore {
        callsLock.withLock { $0.append(.data(data)) }
        return try MusicXMLParser().parse(data: data)
    }

    func parse(fileURL: URL) throws -> MusicXMLScore {
        callsLock.withLock { $0.append(.fileURL(fileURL)) }
        return try MusicXMLParser().parse(data: Data(identityFixtureA.utf8))
    }
}
