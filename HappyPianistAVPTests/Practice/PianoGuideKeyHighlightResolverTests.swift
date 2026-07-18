@testable import HappyPianistAVP
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
        handAssignment: ScoreHandAssignment(hand: .right, provenance: .score)
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
        handAssignment: ScoreHandAssignment(hand: .right, provenance: .score)
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
        handAssignment: ScoreHandAssignment(hand: .left, provenance: .score)
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
        handAssignment: ScoreHandAssignment(hand: .right, provenance: .score)
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
        handAssignment: ScoreHandAssignment(hand: .left, provenance: .score)
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

@Test
func resolverKeepsUnassignedNotesNeutral() {
    let note = PianoHighlightNote(
        occurrenceID: "u0",
        midiNote: 60,
        staff: 3,
        voice: nil,
        velocity: 96,
        onTick: 0,
        offTick: 1,
        fingeringText: nil,
        handAssignment: .unknown
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

    let highlight = PianoGuideKeyHighlightResolver().resolveHighlights(guide: guide)[60]
    #expect(highlight?.hand == .unknown)
    #expect(PianoGuideHighlightStyle.resolve(
        hand: .unknown,
        phase: .triggered,
        keyKind: .white
    ).tintToken == .unassignedHandKey)
}
