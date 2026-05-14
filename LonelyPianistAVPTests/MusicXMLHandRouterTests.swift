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
    let routedScore = MusicXMLHandRouter().routeIfNeeded(score: score)

    let staffByMidi = Dictionary(
        uniqueKeysWithValues: routedScore.notes.compactMap { note -> (Int, Int)? in
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
    let routedScore = MusicXMLHandRouter().routeIfNeeded(score: score)

    let staffByMidi = Dictionary(
        uniqueKeysWithValues: routedScore.notes.compactMap { note -> (Int, Int)? in
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
