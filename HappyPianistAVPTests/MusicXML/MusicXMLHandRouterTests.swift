import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func heuristicRoutingAssignsClearSingleStaffRegistersWithoutChangingScore() throws {
    let score = try MusicXMLParser().parse(fileURL: testFixtureURL("SingleStaffHandRoutingClear.musicxml"))
    let originalStaffAndVoice = score.notes.map { ($0.staff, $0.voice) }

    let result = MusicXMLHandRouter().assignments(for: score)
    let assignmentsByPitch = assignmentsByMIDINote(score: score, result: result)

    #expect(assignmentsByPitch[48]?.hand == .left)
    #expect(assignmentsByPitch[72]?.hand == .right)
    #expect(assignmentsByPitch[48]?.provenance == .heuristic)
    #expect(assignmentsByPitch[72]?.confidence != nil)
    #expect(score.notes.map { ($0.staff, $0.voice) }.elementsEqual(originalStaffAndVoice, by: ==))
}

@Test
func heuristicRoutingIsDeterministicForInterleavingFixture() throws {
    let score = try MusicXMLParser().parse(fileURL: testFixtureURL("SingleStaffHandRoutingInterleaving.musicxml"))

    let first = MusicXMLHandRouter().assignments(for: score)
    let second = MusicXMLHandRouter().assignments(for: score)
    let assignments = assignmentsByMIDINote(score: score, result: first)

    #expect(first == second)
    #expect(assignments[55]?.hand == .left)
    #expect(assignments[57]?.hand == .left)
    #expect(assignments[65]?.hand == .right)
    #expect(assignments[67]?.hand == .right)
}

@Test
func ambiguousSingleStaffMaterialRemainsUnknown() {
    let score = MusicXMLScore(notes: [
        note(sourceOrdinal: 0, midiNote: 59),
        note(sourceOrdinal: 1, midiNote: 60),
        note(sourceOrdinal: 2, midiNote: 61),
        note(sourceOrdinal: 3, midiNote: 72),
    ])

    let result = MusicXMLHandRouter().assignments(for: score)
    let assignments = assignmentsByMIDINote(score: score, result: result)

    #expect(assignments[59]?.hand == .left)
    #expect(assignments[60]?.hand == .unknown)
    #expect(assignments[61]?.hand == .unknown)
    #expect(assignments[72]?.hand == .right)
}

@Test
func existingMultipleStavesAreNeverReinterpretedAsHands() {
    let score = MusicXMLScore(notes: [
        note(sourceOrdinal: 0, midiNote: 48, staff: 2),
        note(sourceOrdinal: 1, midiNote: 72, staff: 1),
    ])

    let result = MusicXMLHandRouter().assignments(for: score)

    #expect(result.assignmentsBySourceNoteID.isEmpty)
    #expect(score.notes.map(\.staff) == [2, 1])
}

private func assignmentsByMIDINote(
    score: MusicXMLScore,
    result: MusicXMLHandRoutingResult
) -> [Int: ScoreHandAssignment] {
    Dictionary(uniqueKeysWithValues: score.notes.compactMap { note in
        guard let midiNote = note.midiNote else { return nil }
        return (midiNote, result.assignment(for: note))
    })
}

private func note(sourceOrdinal: Int, midiNote: Int, staff: Int = 1) -> MusicXMLNoteEvent {
    MusicXMLNoteEvent(
        sourceID: MusicXMLSourceNoteID(
            partID: "P1",
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            staff: staff,
            voice: 1,
            sourceOrdinal: sourceOrdinal
        ),
        partID: "P1",
        measureNumber: 1,
        tick: sourceOrdinal * 120,
        durationTicks: 120,
        midiNote: midiNote,
        isRest: false,
        isChord: false,
        isGrace: false,
        staff: staff,
        voice: 1,
        attackTicks: 0,
        releaseTicks: 0,
        dynamicsOverrideVelocity: nil,
        articulations: [],
        arpeggiate: nil,
        fingerings: []
    )
}

@Test
func crossStaffGoldenFixtureKeepsStaffAndVoiceFactsWithoutInventingHands() throws {
    let fixture = try PianoPerformanceFixtureLoader().fixture(id: "cross-staff-hand-assignment")
    let score = try MusicXMLParser().parse(fileURL: fixture.url)
    let before = score.notes.map { ($0.sourceID, $0.staff, $0.voice, $0.midiNote) }

    let result = MusicXMLHandRouter().assignments(for: score)

    #expect(result.assignmentsBySourceNoteID.isEmpty)
    #expect(score.notes.map { ($0.sourceID, $0.staff, $0.voice, $0.midiNote) }.elementsEqual(before, by: ==))
    #expect(score.notes.map(\.staff) == [1, 2, 1, 2])
    #expect(score.notes.map(\.voice) == [1, 2, 3, 4])
    #expect(score.notes.compactMap(\.sourceID).count == 4)
    #expect(Set(score.notes.compactMap(\.sourceID)).count == 4)
}
