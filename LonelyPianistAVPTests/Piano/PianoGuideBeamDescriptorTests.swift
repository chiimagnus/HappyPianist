@testable import LonelyPianistAVP
import simd
import Testing

@Test
func descriptorsAreEmptyWhenCurrentStepIsNil() {
    let result = PianoGuideBeamDescriptor.makeDescriptors(
        highlightGuide: nil,
        keyboardGeometry: makeGeometry()
    )
    #expect(result.isEmpty)
}

@Test
func descriptorsAreEmptyWhenKeyboardGeometryIsNil() {
    let step = PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)])
    let result = PianoGuideBeamDescriptor.makeDescriptors(
        highlightGuide: makeGuide(from: step),
        keyboardGeometry: nil
    )
    #expect(result.isEmpty)
}

@Test
func descriptorsDeduplicateNotesAndAlignToSurface() {
    let step = PracticeStep(tick: 0, notes: [
        PracticeStepNote(midiNote: 60, staff: nil),
        PracticeStepNote(midiNote: 60, staff: nil),
    ])
    let geometry = makeGeometry()

    let result = PianoGuideBeamDescriptor.makeDescriptors(
        highlightGuide: makeGuide(from: step),
        keyboardGeometry: geometry
    )

    #expect(result.count == 1)
    let descriptor = result.first
    #expect(descriptor?.midiNote == 60)

    let key = geometry.key(for: 60)
    let epsilonMeters: Float = 0.0015
    #expect(abs((descriptor?.positionLocal.y ?? -1) - ((key?.surfaceLocalY ?? 0) + epsilonMeters)) < 1e-6)
}

@Test
func descriptorUsesFootprintAndMinimumSizes() {
    let step = PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)])
    let geometry = makeGeometry(beamWidth: 0.002, beamDepth: 0.006)

    let result = PianoGuideBeamDescriptor.makeDescriptors(
        highlightGuide: makeGuide(from: step),
        keyboardGeometry: geometry
    )

    let descriptor = result.first
    let insetScale: Float = 0.98
    let thicknessMeters: Float = 0.001
    #expect(abs((descriptor?.sizeLocal.x ?? 0) - (0.02 * insetScale)) < 1e-6)
    #expect(abs((descriptor?.sizeLocal.y ?? 0) - thicknessMeters) < 1e-6)
    #expect(abs((descriptor?.sizeLocal.z ?? 0) - (0.14 * insetScale)) < 1e-6)
}

@Test
func descriptorIDIncludesGuideIDToSupportRepeatedOccurrences() {
    let step = PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)])
    let geometry = makeGeometry()

    let guide = makeGuide(from: step)
    let next = PianoHighlightGuide(
        id: guide.id + 1,
        kind: guide.kind,
        tick: guide.tick,
        durationTicks: guide.durationTicks,
        practiceStepIndex: guide.practiceStepIndex,
        activeNotes: guide.activeNotes,
        triggeredNotes: guide.triggeredNotes,
        releasedMIDINotes: guide.releasedMIDINotes
    )

    let first = PianoGuideBeamDescriptor.makeDescriptors(
        highlightGuide: guide,
        keyboardGeometry: geometry
    ).first
    let second = PianoGuideBeamDescriptor.makeDescriptors(
        highlightGuide: next,
        keyboardGeometry: geometry
    ).first

    #expect(first?.id != second?.id)
}

private func makeGeometry(beamWidth: Float = 0.04, beamDepth: Float = 0.06) -> PianoKeyboardGeometry {
    let frame = KeyboardFrame(
        a0World: SIMD3<Float>(0.0, 0.5, 0.0),
        c8World: SIMD3<Float>(1.0, 0.5, 0.0),
        planeHeight: 0.5
    )!

    let key = PianoKeyGeometry(
        midiNote: 60,
        kind: .white,
        localCenter: SIMD3<Float>(0.0, -0.015, -0.07),
        localSize: SIMD3<Float>(0.02, 0.03, 0.14),
        surfaceLocalY: 0.0,
        hitCenterLocal: SIMD3<Float>(0.0, -0.015, -0.07),
        hitSizeLocal: SIMD3<Float>(0.02, 0.03, 0.14),
        beamFootprintCenterLocal: SIMD3<Float>(0.0, 0.0, -0.07),
        beamFootprintSizeLocal: SIMD2<Float>(beamWidth, beamDepth)
    )

    return PianoKeyboardGeometry(frame: frame, keys: [key])
}

private func makeGuide(from step: PracticeStep) -> PianoHighlightGuide {
    let notes = step.notes.enumerated().map { index, note in
        PianoHighlightNote(
            occurrenceID: "test-\(step.tick)-\(index)-\(note.midiNote)",
            midiNote: note.midiNote,
            staff: note.staff,
            voice: nil,
            velocity: note.velocity,
            onTick: step.tick + note.onTickOffset,
            offTick: step.tick + note.onTickOffset + 1,
            fingeringText: note.fingeringText
        )
    }
    return PianoHighlightGuide(
        id: step.tick + 1,
        kind: .trigger,
        tick: step.tick,
        durationTicks: nil,
        practiceStepIndex: nil,
        activeNotes: notes,
        triggeredNotes: notes,
        releasedMIDINotes: []
    )
}
