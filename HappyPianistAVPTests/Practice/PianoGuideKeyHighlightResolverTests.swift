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
func resolverKeepsConflictingStavesNeutralWhenNotesShareMIDINote() {
    let upper = PianoHighlightNote(
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
    let lower = PianoHighlightNote(
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
        triggeredNotes: [upper, lower],
        releasedMIDINotes: []
    )

    let highlights = PianoGuideKeyHighlightResolver().resolveHighlights(guide: guide)
    #expect(highlights[60]?.staffNumber == nil)
}

@Test
func resolverUsesTriggeredNotesStaffBeforeActiveNotes() {
    let triggeredUpper = PianoHighlightNote(
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
    let activeLower = PianoHighlightNote(
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
        activeNotes: [activeLower],
        triggeredNotes: [triggeredUpper],
        releasedMIDINotes: []
    )

    let highlights = PianoGuideKeyHighlightResolver().resolveHighlights(guide: guide)
    #expect(highlights[60]?.staffNumber == 1)
}

@Test
func resolverKeepsAdditionalStaffNeutral() {
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
    #expect(highlight?.staffNumber == 3)
    #expect(PianoGuideHighlightStyle.resolve(
        staffNumber: highlight?.staffNumber,
        phase: .triggered,
        keyKind: .white
    ).tintToken == .unassignedStaffKey)
}
