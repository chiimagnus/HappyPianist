import Foundation
@testable import HappyPianistAVP
import Testing

private let identityFixtureA = """
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes><note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note></measure></part>
</score-partwise>
"""

private let identityFixtureB = identityFixtureA.replacing("<step>C</step>", with: "<step>D</step>")

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

    try Data(identityFixtureB.utf8).write(to: url)
    let replaced = try await service.prepare(songID: songID, from: url, file: file)
    #expect(replaced.identity.scoreRevision != first.identity.scoreRevision)
}
