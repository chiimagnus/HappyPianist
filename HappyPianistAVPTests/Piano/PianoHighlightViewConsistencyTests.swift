@testable import HappyPianistAVP
import simd
import Testing

@Test
func pianoKeyboardKeyViewIDChangesWhenOccurrenceChanges() {
    let first = PianoKeyboard88View.highlightKeyViewID(
        isBlackKey: false,
        midiNote: 60,
        highlightOccurrenceID: 1,
        isHighlighted: true
    )
    let second = PianoKeyboard88View.highlightKeyViewID(
        isBlackKey: false,
        midiNote: 60,
        highlightOccurrenceID: 2,
        isHighlighted: true
    )

    #expect(first != second)
}

@Test
func highlightGuide2DAnd3DUseSameMIDINoteSet() {
    let notes: [PianoHighlightNote] = [
        PianoHighlightNote(
            occurrenceID: "o-60",
            midiNote: 60,
            staff: 1,
            voice: 1,
            velocity: 96,
            onTick: 0,
            offTick: 480,
            fingerings: [],
            handAssignment: .unknown
        ),
        PianoHighlightNote(
            occurrenceID: "o-64",
            midiNote: 64,
            staff: 2,
            voice: 1,
            velocity: 96,
            onTick: 0,
            offTick: 480,
            fingerings: [],
            handAssignment: .unknown
        ),
    ]
    let guide = PianoHighlightGuide(
        id: 41,
        kind: .trigger,
        tick: 0,
        durationTicks: nil,
        practiceStepIndex: 0,
        activeNotes: notes,
        triggeredNotes: notes,
        releasedMIDINotes: []
    )

    let geometry = makeGeometry(for: [60, 64])
    let descriptors = PianoGuideBeamDescriptor.makeDescriptors(
        highlightGuide: guide,
        keyboardGeometry: geometry
    )

    #expect(Set(descriptors.map(\.midiNote)) == guide.highlightedMIDINotes)
    #expect(Set(descriptors.map(\.guideID)) == [41])
    #expect(Dictionary(uniqueKeysWithValues: descriptors.map { ($0.midiNote, $0.staffNumber) }) == [
        60: 1,
        64: 2,
    ])
}

@Test
func highlightGuide2D3DAndNotationUseSameMIDINoteSet() {
    let score = MusicXMLScore(notes: [
        consistencyNote(ordinal: 0, midiNote: 60, step: "C", octave: 4, staff: 1),
        consistencyNote(ordinal: 1, midiNote: 64, step: "E", octave: 3, staff: 2),
    ])
    let plan = makeTestScorePerformancePlan(from: score)
    let highlightNotes = plan.noteEvents.map {
        PianoHighlightNote(
            occurrenceID: $0.performedNoteID.description,
            midiNote: $0.midiNote,
            staff: $0.staff,
            voice: $0.voice,
            velocity: $0.velocityResolution.velocity,
            onTick: $0.performedOnTick,
            offTick: $0.performedOffTick,
            fingerings: $0.fingerings,
            handAssignment: $0.handAssignment
        )
    }
    let guide = PianoHighlightGuide(
        id: 42,
        kind: .trigger,
        tick: 0,
        durationTicks: nil,
        practiceStepIndex: 0,
        activeNotes: highlightNotes,
        triggeredNotes: highlightNotes,
        releasedMIDINotes: []
    )
    let descriptors = PianoGuideBeamDescriptor.makeDescriptors(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(for: [60, 64])
    )
    let projection = ScoreNotationProjection(plan: plan, sourceScore: score)
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: projection,
        overlay: .init(activeEventIDs: Set(plan.noteEvents.map(\.id)), activeTickRange: nil)
    )
    let notationOccurrenceIDs = Set(layout.items.filter(\.isHighlighted).map(\.occurrenceID))
    let plannedOccurrenceIDs = Set(plan.noteEvents.flatMap(\.contributingPerformedNoteIDs).map(\.description))

    #expect(guide.highlightedMIDINotes == Set(descriptors.map(\.midiNote)))
    #expect(notationOccurrenceIDs == plannedOccurrenceIDs)
}

@Test
func repeatedOccurrenceChangesBoth2DKeyViewIDAnd3DDescriptorID() {
    let keyID1 = PianoKeyboard88View.highlightKeyViewID(
        isBlackKey: false,
        midiNote: 60,
        highlightOccurrenceID: 101,
        isHighlighted: true
    )
    let keyID2 = PianoKeyboard88View.highlightKeyViewID(
        isBlackKey: false,
        midiNote: 60,
        highlightOccurrenceID: 102,
        isHighlighted: true
    )
    #expect(keyID1 != keyID2)

    let note = PianoHighlightNote(
        occurrenceID: "o-60",
        midiNote: 60,
        staff: 1,
        voice: 1,
        velocity: 96,
        onTick: 0,
        offTick: 1,
        fingerings: [],
        handAssignment: .unknown
    )
    let geometry = makeGeometry(for: [60])
    let guide1 = PianoHighlightGuide(
        id: 101,
        kind: .trigger,
        tick: 0,
        durationTicks: nil,
        practiceStepIndex: 0,
        activeNotes: [note],
        triggeredNotes: [note],
        releasedMIDINotes: []
    )
    let guide2 = PianoHighlightGuide(
        id: 102,
        kind: .trigger,
        tick: 0,
        durationTicks: nil,
        practiceStepIndex: 0,
        activeNotes: [note],
        triggeredNotes: [note],
        releasedMIDINotes: []
    )

    let first = PianoGuideBeamDescriptor.makeDescriptors(
        highlightGuide: guide1,
        keyboardGeometry: geometry
    )
    let second = PianoGuideBeamDescriptor.makeDescriptors(
        highlightGuide: guide2,
        keyboardGeometry: geometry
    )

    #expect(first.count == 1)
    #expect(second.count == 1)
    #expect(first.first?.id != second.first?.id)
}

private func makeGeometry(for midiNotes: [Int]) -> PianoKeyboardGeometry {
    let frame = KeyboardFrame(
        a0World: SIMD3<Float>(0.0, 0.5, 0.0),
        c8World: SIMD3<Float>(1.0, 0.5, 0.0),
        planeHeight: 0.5
    )!

    let keys = midiNotes.enumerated().map { index, midiNote in
        PianoKeyGeometry(
            midiNote: midiNote,
            kind: .white,
            localCenter: SIMD3<Float>(Float(index) * 0.02, -0.015, -0.07),
            localSize: SIMD3<Float>(0.02, 0.03, 0.14),
            surfaceLocalY: 0.0,
            hitCenterLocal: SIMD3<Float>(Float(index) * 0.02, -0.015, -0.07),
            hitSizeLocal: SIMD3<Float>(0.02, 0.03, 0.14),
            beamFootprintCenterLocal: SIMD3<Float>(Float(index) * 0.02, 0.0, -0.07),
            beamFootprintSizeLocal: SIMD2<Float>(0.04, 0.06)
        )
    }

    return PianoKeyboardGeometry(frame: frame, keys: keys)
}

private func consistencyNote(
    ordinal: Int,
    midiNote: Int,
    step: String,
    octave: Int,
    staff: Int
) -> MusicXMLNoteEvent {
    MusicXMLNoteEvent(
        sourceID: MusicXMLSourceNoteID(
            partID: "P1",
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            staff: staff,
            voice: 1,
            sourceOrdinal: ordinal
        ),
        partID: "P1",
        measureNumber: 1,
        tick: 0,
        durationTicks: 480,
        writtenPitch: MusicXMLWrittenPitch(step: step, octave: octave),
        writtenRhythm: MusicXMLWrittenRhythm(typeToken: "quarter"),
        midiNote: midiNote,
        isRest: false,
        isChord: false,
        staff: staff,
        voice: 1
    )
}
