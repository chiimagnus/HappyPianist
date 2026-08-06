import MusicXML
import Practice
@testable import HappyPianistAVP
import simd
import Testing

@Test
func resolverUsesScoreFingeringForBothHands() {
    let guide = makeGuide(
        triggered: [
            makeNote(id: "right", midiNote: 60, hand: .right, fingering: "1"),
            makeNote(id: "left", midiNote: 48, hand: .left, fingering: "5"),
        ]
    )

    let targets = PianoDemonstrationHandTargetResolver().resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [48, 60])
    )

    #expect(targets.targets(for: .right).first?.finger == .thumb)
    #expect(targets.targets(for: .left).first?.finger == .little)
    #expect(targets.targets(for: .right).first?.phase == .triggered)
    #expect(targets.targets(for: .right).first?.contactPositionLocal.y == 0)
}

@Test
func resolverUsesStableMirrorAwareFallbackForChord() {
    let guide = makeGuide(
        triggered: [
            makeNote(id: "r0", midiNote: 60, hand: .right),
            makeNote(id: "r1", midiNote: 64, hand: .right),
            makeNote(id: "r2", midiNote: 67, hand: .right),
            makeNote(id: "l0", midiNote: 48, hand: .left),
            makeNote(id: "l1", midiNote: 52, hand: .left),
        ]
    )
    let resolver = PianoDemonstrationHandTargetResolver()
    let geometry = makeGeometry(notes: [48, 52, 60, 64, 67])

    let first = resolver.resolve(highlightGuide: guide, keyboardGeometry: geometry)
    let second = resolver.resolve(highlightGuide: guide, keyboardGeometry: geometry)

    #expect(first == second)
    #expect(first.targets(for: .right).map(\.finger) == [.thumb, .index, .middle])
    #expect(first.targets(for: .left).map(\.finger) == [.little, .ring])
}

@Test
func resolverKeepsHeldTargetsAndReportsReleasedNotes() {
    let guide = makeGuide(
        active: [makeNote(id: "held", midiNote: 60, hand: .right)],
        triggered: [makeNote(id: "triggered", midiNote: 64, hand: .right)],
        released: [55]
    )

    let targets = PianoDemonstrationHandTargetResolver().resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [60, 64])
    )

    #expect(targets.targets.first { $0.occurrenceID == "held" }?.phase == .held)
    #expect(targets.targets.first { $0.occurrenceID == "triggered" }?.phase == .triggered)
    #expect(targets.releasedMIDINotes == [55])
}

@Test
func resolverSkipsUnknownAndOverloadedHandsWithoutInventingTargets() {
    let unknown = makeNote(id: "unknown", midiNote: 60, hand: .unknown)
    let overloaded = (0 ... 5).map { index in
        makeNote(id: "right-\(index)", midiNote: 61 + index, hand: .right)
    }
    let guide = makeGuide(triggered: [unknown] + overloaded)

    let targets = PianoDemonstrationHandTargetResolver().resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [60] + overloaded.map(\.midiNote))
    )

    #expect(targets.targets.isEmpty)
}

@Test
func resolverRejectsInvalidOrConflictingFingerings() {
    let guide = makeGuide(
        triggered: [
            makeNote(id: "invalid", midiNote: 60, hand: .right, fingering: "9"),
            makeNote(id: "first", midiNote: 62, hand: .right, fingering: "1"),
            makeNote(id: "conflict", midiNote: 64, hand: .right, fingering: "1"),
        ]
    )

    let targets = PianoDemonstrationHandTargetResolver().resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [60, 62, 64])
    )

    #expect(targets.targets.map(\.occurrenceID) == ["invalid", "first"])
    #expect(targets.targets.map(\.finger) == [.index, .thumb])
}

@Test
func resolverReturnsEmptyWithoutGuideOrGeometry() {
    let resolver = PianoDemonstrationHandTargetResolver()

    #expect(resolver.resolve(highlightGuide: nil, keyboardGeometry: makeGeometry(notes: [60])) == .empty)
    #expect(resolver.resolve(highlightGuide: makeGuide(triggered: []), keyboardGeometry: nil) == .empty)
}

private func makeGuide(
    active: [PianoHighlightNote] = [],
    triggered: [PianoHighlightNote],
    released: Set<Int> = []
) -> PianoHighlightGuide {
    PianoHighlightGuide(
        id: 1,
        kind: triggered.isEmpty ? .release : .trigger,
        tick: 0,
        durationTicks: 1,
        practiceStepIndex: 0,
        activeNotes: active,
        triggeredNotes: triggered,
        releasedMIDINotes: released
    )
}

private func makeNote(
    id: String,
    midiNote: Int,
    hand: ScoreHand,
    fingering: String? = nil
) -> PianoHighlightNote {
    let fingerings = fingering.map {
        [MusicXMLFingering(text: $0, provenance: .score)]
    } ?? []
    return PianoHighlightNote(
        occurrenceID: id,
        midiNote: midiNote,
        staff: hand == .left ? 2 : 1,
        voice: nil,
        velocity: 96,
        onTick: 0,
        offTick: 1,
        fingerings: fingerings,
        handAssignment: ScoreHandAssignment(
            hand: hand,
            provenance: hand == .unknown ? .unresolved : .score
        )
    )
}

private func makeGeometry(notes: [Int]) -> PianoKeyboardGeometry {
    let frame = KeyboardFrame(
        a0World: SIMD3<Float>(0, 0.5, 0),
        c8World: SIMD3<Float>(1, 0.5, 0),
        planeHeight: 0.5
    )!
    let keys = notes.enumerated().map { index, midiNote in
        PianoKeyGeometry(
            midiNote: midiNote,
            kind: .white,
            localCenter: SIMD3<Float>(Float(index) * 0.024, -0.015, -0.07),
            localSize: SIMD3<Float>(0.022, 0.03, 0.14),
            surfaceLocalY: 0,
            hitCenterLocal: SIMD3<Float>(Float(index) * 0.024, -0.015, -0.07),
            hitSizeLocal: SIMD3<Float>(0.022, 0.03, 0.14),
            beamFootprintCenterLocal: SIMD3<Float>(Float(index) * 0.024, 0, -0.07),
            beamFootprintSizeLocal: SIMD2<Float>(0.022, 0.14)
        )
    }
    return PianoKeyboardGeometry(frame: frame, keys: keys)
}
