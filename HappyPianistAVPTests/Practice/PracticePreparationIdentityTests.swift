import Foundation
@testable import HappyPianistAVP
import os
import Testing

private let identityFixtureA = """
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes><note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note></measure></part>
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

@Test
func preparationKeepsExactSongIDAndStableRevision() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appending(path: "score.musicxml")
    try Data(identityFixtureA.utf8).write(to: url)
    let songID = UUID()
    let file = ImportedMusicXMLFile(fileName: "Fixture", storedURL: url, importedAt: .now)
    let service = PracticePreparationService()

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

    let service = PracticePreparationService()
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
}

@Test
func splitPianoPreparationUsesThePartThatOwnsStructureDirectives() async throws {
    let url = testFixtureURL("SplitPartGrandStaffPiano.musicxml")
    let prepared = try await PracticePreparationService().prepare(
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
func plainMusicXMLPreparationParsesTheAlreadyReadBytes() async throws {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "single-read-\(UUID().uuidString).musicxml"
    )
    let scoreBytes = Data(identityFixtureA.utf8)
    try scoreBytes.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let parser = RecordingPreparationParser()
    let service = PracticePreparationService(parser: parser)

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
    let service = PracticePreparationService(parser: parser)

    _ = try await service.prepare(
        songID: UUID(),
        from: url,
        file: ImportedMusicXMLFile(fileName: "Archive", storedURL: url, importedAt: .now)
    )

    #expect(parser.calls == [.fileURL(url)])
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
