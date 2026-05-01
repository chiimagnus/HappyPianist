@testable import LonelyPianistAVP
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
            fingeringText: nil
        ),
        PianoHighlightNote(
            occurrenceID: "o-64",
            midiNote: 64,
            staff: 1,
            voice: 1,
            velocity: 96,
            onTick: 0,
            offTick: 480,
            fingeringText: nil
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
        fingeringText: nil
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
