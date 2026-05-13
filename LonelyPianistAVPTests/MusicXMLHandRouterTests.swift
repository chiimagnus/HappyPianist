import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func heuristicRoutingSplitsClearSingleStaffFixture() throws {
    let fixtureURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures")
        .appending(path: "SingleStaffHandRoutingClear.musicxml")

    let score = try MusicXMLParser().parse(fileURL: fixtureURL)
    let file = ImportedMusicXMLFile(fileName: fixtureURL.lastPathComponent, storedURL: fixtureURL, importedAt: .now)

    let result = MusicXMLHandRouter().routeIfNeeded(score: score, file: file)

    #expect(result.strategy == .heuristic)

    let staffByMidi = Dictionary(
        uniqueKeysWithValues: result.routedScore.notes.compactMap { note -> (Int, Int)? in
            guard note.isRest == false else { return nil }
            guard let midiNote = note.midiNote else { return nil }
            guard let staff = note.staff else { return nil }
            return (midiNote, staff)
        }
    )

    #expect(staffByMidi[48] == 2)
    #expect(staffByMidi[72] == 1)
}

@Test
func heuristicRoutingIsDeterministicForInterleavingFixture() throws {
    let fixtureURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures")
        .appending(path: "SingleStaffHandRoutingInterleaving.musicxml")

    let score = try MusicXMLParser().parse(fileURL: fixtureURL)
    let file = ImportedMusicXMLFile(fileName: fixtureURL.lastPathComponent, storedURL: fixtureURL, importedAt: .now)

    let result = MusicXMLHandRouter().routeIfNeeded(score: score, file: file)

    #expect(result.strategy == .heuristic)

    let staffByMidi = Dictionary(
        uniqueKeysWithValues: result.routedScore.notes.compactMap { note -> (Int, Int)? in
            guard note.isRest == false else { return nil }
            guard let midiNote = note.midiNote else { return nil }
            guard let staff = note.staff else { return nil }
            return (midiNote, staff)
        }
    )

    #expect(staffByMidi[55] == 2)
    #expect(staffByMidi[57] == 2)
    #expect(staffByMidi[65] == 1)
    #expect(staffByMidi[67] == 1)
}

@Test
func perScoreOverrideCanDisableHeuristicRouting() throws {
    let fixtureURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures")
        .appending(path: "SingleStaffHandRoutingClear.musicxml")

    let score = try MusicXMLParser().parse(fileURL: fixtureURL)
    let file = ImportedMusicXMLFile(fileName: fixtureURL.lastPathComponent, storedURL: fixtureURL, importedAt: .now)
    let store = MusicXMLHandRoutingOverrideStore()

    store.saveOverride(.disableHeuristic, for: file)
    defer { store.saveOverride(nil, for: file) }

    let result = MusicXMLHandRouter().routeIfNeeded(score: score, file: file)

    #expect(result.strategy == .staffBased)
    #expect(result.routedScore.notes.compactMap(\.staff).isEmpty)
}

