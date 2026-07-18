@testable import HappyPianistAVP
import Testing

@Test
func buildStepsGroupsNotesByTickAndMergesHands() {
    let score = MusicXMLScore(notes: [
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 2,
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 2,
            midiNote: 64,
            isRest: false,
            isChord: true,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 2,
            midiNote: 48,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 2,
            voice: 2
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 2,
            durationTicks: 2,
            midiNote: 67,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1
        ),
    ])

    let result = PracticeStepBuilder().buildSteps(from: score)
    #expect(result.steps.count == 2)
    #expect(result.steps[0].tick == 0)
    #expect(result.steps[0].notes.map(\.midiNote) == [48, 60, 64])
    #expect(result.steps[0].notes.map(\.hand) == [.left, .right, .right])
    #expect(result.steps[1].tick == 2)
    #expect(result.steps[1].notes.map(\.midiNote) == [67])
    #expect(result.steps[1].notes.map(\.hand) == [.right])
}

@Test
func buildStepsFiltersRestAndOutOfRangeNotes() {
    let score = MusicXMLScore(notes: [
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 1,
            midiNote: nil,
            isRest: true,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: nil,
            voice: nil
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 1,
            midiNote: 10,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: nil,
            voice: nil
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 1,
            midiNote: 110,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: nil,
            voice: nil
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 1,
            durationTicks: 1,
            midiNote: 72,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1
        ),
    ])

    let result = PracticeStepBuilder().buildSteps(from: score)
    #expect(result.unsupportedNoteCount == 2)
    #expect(result.steps.count == 1)
    #expect(result.steps[0].tick == 1)
    #expect(result.steps[0].notes.map(\.midiNote) == [72])
}

@Test
func buildStepsSkipsTieStopEvents() {
    let score = MusicXMLScore(notes: [
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: true,
            tieStop: false,
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 480,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: true,
            staff: 1,
            voice: 1
        ),
    ])

    let result = PracticeStepBuilder().buildSteps(from: score)
    #expect(result.steps.count == 1)
    #expect(result.steps[0].tick == 0)
    #expect(result.steps[0].notes.map(\.midiNote) == [60])
}

@Test
func buildStepsIncludesGraceNotesWhenEnabled() {
    let score = MusicXMLScore(notes: [
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 480,
            durationTicks: 0,
            midiNote: 60,
            isRest: false,
            isChord: false,
            isGrace: true,
            graceSlash: false,
            graceStealTimePrevious: nil,
            graceStealTimeFollowing: 0.25,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 480,
            durationTicks: 480,
            midiNote: 62,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1
        ),
    ])

    let result = PracticeStepBuilder().buildSteps(
        from: score,
        expressivity: MusicXMLExpressivityOptions(graceEnabled: true)
    )
    #expect(result.steps.map(\.tick) == [480])
    #expect(result.steps[0].notes.map(\.midiNote) == [60, 62])
    #expect(result.steps[0].notes.map(\.onTickOffset) == [0, 120])
}

@Test
func buildStepsSetsOnTickOffsetsForArpeggiateChordWhenEnabled() {
    let score = MusicXMLScore(notes: [
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1,
            arpeggiate: MusicXMLArpeggiate(numberToken: nil, directionToken: nil)
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 64,
            isRest: false,
            isChord: true,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1,
            arpeggiate: MusicXMLArpeggiate(numberToken: nil, directionToken: nil)
        ),
    ])

    let result = PracticeStepBuilder().buildSteps(
        from: score,
        expressivity: MusicXMLExpressivityOptions(arpeggiateEnabled: true)
    )
    #expect(result.steps.count == 1)
    #expect(result.steps[0].tick == 0)
    #expect(result.steps[0].notes.map(\.midiNote) == [60, 64])
    #expect(result.steps[0].notes[0].onTickOffset == 0)
    #expect(result.steps[0].notes[1].onTickOffset == 30)
}

@Test
func buildStepsCarriesFingeringTextIntoStepNotes() {
    let score = MusicXMLScore(notes: [
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1,
            fingeringText: "1"
        ),
    ])

    let result = PracticeStepBuilder().buildSteps(from: score)
    #expect(result.steps.count == 1)
    #expect(result.steps[0].notes.count == 1)
    #expect(result.steps[0].notes[0].fingeringText == "1")
}

@Test
func buildStepsPreservesSameMidiAcrossStaffAndVoiceIdentities() {
    let score = MusicXMLScore(notes: [
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 2,
            midiNote: 60,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 3,
            midiNote: 60,
            isRest: false,
            isChord: true,
            tieStart: false,
            tieStop: false,
            staff: 2,
            voice: 2
        ),
    ])

    let result = PracticeStepBuilder().buildSteps(from: score)

    #expect(result.steps.count == 1)
    #expect(result.steps[0].notes.count == 2)
    #expect(result.steps[0].notes.map(\.midiNote) == [60, 60])
    #expect(result.steps[0].notes.map { $0.staff ?? -1 } == [1, 2])
    #expect(result.steps[0].notes.map { $0.voice ?? -1 } == [1, 2])
}

@Test
func stepAndSpanProjectionsShareCanonicalPerformedOnsets() {
    let notes = [
        MusicXMLNoteEvent(
            partID: "P1", measureNumber: 1, tick: 480, durationTicks: 0, midiNote: 59,
            isRest: false, isChord: false, isGrace: true,
            graceStealTimeFollowing: 0.25,
            tieStart: false, tieStop: false, staff: 1, voice: 1
        ),
        MusicXMLNoteEvent(
            partID: "P1", measureNumber: 1, tick: 480, durationTicks: 480, midiNote: 60,
            isRest: false, isChord: false,
            tieStart: false, tieStop: false, staff: 1, voice: 1
        ),
        MusicXMLNoteEvent(
            partID: "P1", measureNumber: 1, tick: 960, durationTicks: 480, midiNote: 64,
            isRest: false, isChord: false,
            tieStart: false, tieStop: false, staff: 1, voice: 1,
            arpeggiate: MusicXMLArpeggiate(numberToken: "1", directionToken: nil)
        ),
        MusicXMLNoteEvent(
            partID: "P1", measureNumber: 1, tick: 960, durationTicks: 480, midiNote: 67,
            isRest: false, isChord: true,
            tieStart: false, tieStop: false, staff: 1, voice: 1,
            arpeggiate: MusicXMLArpeggiate(numberToken: "1", directionToken: nil)
        ),
    ]
    let score = MusicXMLScore(notes: notes)
    let expressivity = MusicXMLExpressivityOptions(graceEnabled: true, arpeggiateEnabled: true)
    let steps = PracticeStepBuilder().buildSteps(
        from: score,
        expressivity: expressivity,
        handAssignments: [:]
    ).steps
    let spans = MusicXMLNoteSpanBuilder().buildSpans(from: notes, expressivity: expressivity)
    let onsetByMIDINote = Dictionary(uniqueKeysWithValues: spans.map { ($0.midiNote, $0.onTick) })

    for step in steps {
        for note in step.notes {
            #expect(onsetByMIDINote[note.midiNote] == step.tick + note.onTickOffset)
        }
    }
}
