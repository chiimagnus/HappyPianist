import Testing
@testable import LonelyPianistAVP

@Test
func buildStepsGroupsNotesByTickAndMergesHands() {
    let score = MusicXMLScore(notes: [
        MusicXMLNoteEvent(partID: "P1", measureNumber: 1, tick: 0, durationTicks: 2, midiNote: 60, isRest: false, isChord: false, staff: 1, voice: 1),
        MusicXMLNoteEvent(partID: "P1", measureNumber: 1, tick: 0, durationTicks: 2, midiNote: 64, isRest: false, isChord: true, staff: 1, voice: 1),
        MusicXMLNoteEvent(partID: "P1", measureNumber: 1, tick: 0, durationTicks: 2, midiNote: 48, isRest: false, isChord: false, staff: 2, voice: 2),
        MusicXMLNoteEvent(partID: "P1", measureNumber: 1, tick: 2, durationTicks: 2, midiNote: 67, isRest: false, isChord: false, staff: 1, voice: 1)
    ])

    let result = PracticeStepBuilder().buildSteps(from: score)
    #expect(result.steps.count == 2)
    #expect(result.steps[0].tick == 0)
    #expect(result.steps[0].notes.map(\.midiNote) == [48, 60, 64])
    #expect(result.steps[1].tick == 2)
    #expect(result.steps[1].notes.map(\.midiNote) == [67])
}

@Test
func buildStepsFiltersRestAndOutOfRangeNotes() {
    let score = MusicXMLScore(notes: [
        MusicXMLNoteEvent(partID: "P1", measureNumber: 1, tick: 0, durationTicks: 1, midiNote: nil, isRest: true, isChord: false, staff: nil, voice: nil),
        MusicXMLNoteEvent(partID: "P1", measureNumber: 1, tick: 0, durationTicks: 1, midiNote: 10, isRest: false, isChord: false, staff: nil, voice: nil),
        MusicXMLNoteEvent(partID: "P1", measureNumber: 1, tick: 0, durationTicks: 1, midiNote: 110, isRest: false, isChord: false, staff: nil, voice: nil),
        MusicXMLNoteEvent(partID: "P1", measureNumber: 1, tick: 1, durationTicks: 1, midiNote: 72, isRest: false, isChord: false, staff: 1, voice: 1)
    ])

    let result = PracticeStepBuilder().buildSteps(from: score)
    #expect(result.unsupportedNoteCount == 2)
    #expect(result.steps.count == 1)
    #expect(result.steps[0].tick == 1)
    #expect(result.steps[0].notes.map(\.midiNote) == [72])
}
