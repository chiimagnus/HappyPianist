@testable import LonelyPianistAVP
import Testing

@Test
func resolverMarksTriggeredNotesAsTriggered() {
    let note = PianoHighlightNote(
        occurrenceID: "t0",
        midiNote: 60,
        staff: 1,
        voice: nil,
        velocity: 96,
        onTick: 0,
        offTick: 1,
        fingeringText: nil,
        hand: .right
    )

    let guide = PianoHighlightGuide(
        id: 1,
        kind: .trigger,
        tick: 0,
        durationTicks: nil,
        practiceStepIndex: nil,
        activeNotes: [],
        triggeredNotes: [note],
        releasedMIDINotes: []
    )

    let highlights = PianoGuideKeyHighlightResolver().resolveHighlights(guide: guide)
    #expect(highlights[60]?.phase == .triggered)
}

@Test
func resolverPrefersLeftHandWhenMultipleNotesShareMIDINote() {
    let right = PianoHighlightNote(
        occurrenceID: "t0",
        midiNote: 60,
        staff: 1,
        voice: nil,
        velocity: 96,
        onTick: 0,
        offTick: 1,
        fingeringText: nil,
        hand: .right
    )
    let left = PianoHighlightNote(
        occurrenceID: "t1",
        midiNote: 60,
        staff: 2,
        voice: nil,
        velocity: 96,
        onTick: 0,
        offTick: 1,
        fingeringText: nil,
        hand: .left
    )

    let guide = PianoHighlightGuide(
        id: 1,
        kind: .trigger,
        tick: 0,
        durationTicks: nil,
        practiceStepIndex: nil,
        activeNotes: [],
        triggeredNotes: [right, left],
        releasedMIDINotes: []
    )

    let highlights = PianoGuideKeyHighlightResolver().resolveHighlights(guide: guide)
    #expect(highlights[60]?.hand == .left)
}

@Test
func resolverUsesTriggeredNotesHandPreferenceBeforeActiveNotes() {
    let triggeredRight = PianoHighlightNote(
        occurrenceID: "t0",
        midiNote: 60,
        staff: 1,
        voice: nil,
        velocity: 96,
        onTick: 0,
        offTick: 1,
        fingeringText: nil,
        hand: .right
    )
    let activeLeft = PianoHighlightNote(
        occurrenceID: "a0",
        midiNote: 60,
        staff: 2,
        voice: nil,
        velocity: 96,
        onTick: 0,
        offTick: 1,
        fingeringText: nil,
        hand: .left
    )

    let guide = PianoHighlightGuide(
        id: 1,
        kind: .trigger,
        tick: 0,
        durationTicks: nil,
        practiceStepIndex: nil,
        activeNotes: [activeLeft],
        triggeredNotes: [triggeredRight],
        releasedMIDINotes: []
    )

    let highlights = PianoGuideKeyHighlightResolver().resolveHighlights(guide: guide)
    #expect(highlights[60]?.hand == .right)
}
