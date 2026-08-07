@testable import HappyPianistAVP
import MusicXML
import Practice
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

    let coverage = PianoDemonstrationHandTargetResolver().resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [48, 60])
    )

    #expect(coverage.coveredTargets(for: .right).first?.finger == .thumb)
    #expect(coverage.coveredTargets(for: .left).first?.finger == .little)
    #expect(coverage.coveredTargets(for: .right).first?.phase == .triggered)
    #expect(coverage.coveredTargets(for: .right).first?.contactPositionLocal.y == 0)
    #expect(coverage.uncoveredKeys.isEmpty)
}

@Test
func resolverUsesGrandStaffForUnassignedDemonstrationHands() {
    let guide = makeGuide(
        triggered: [
            makeNote(id: "upper", midiNote: 60, hand: .unknown, staff: 1),
            makeNote(id: "lower", midiNote: 48, hand: .unknown, staff: 2),
        ]
    )

    let coverage = PianoDemonstrationHandTargetResolver().resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [48, 60])
    )

    #expect(coverage.coveredTargets(for: .right).map(\.midiNote) == [60])
    #expect(coverage.coveredTargets(for: .left).map(\.midiNote) == [48])
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
    #expect(first.coveredTargets(for: .right).map(\.finger) == [.thumb, .index, .middle])
    #expect(first.coveredTargets(for: .left).map(\.finger) == [.little, .ring])
}

@Test
func resolverKeepsHeldTargetsAndReportsReleasedNotes() {
    let guide = makeGuide(
        active: [makeNote(id: "held", midiNote: 60, hand: .right)],
        triggered: [makeNote(id: "triggered", midiNote: 64, hand: .right)],
        released: [55]
    )

    let coverage = PianoDemonstrationHandTargetResolver().resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [60, 64])
    )

    #expect(coverage.coveredTargets.first { $0.occurrenceID == "held" }?.phase == .held)
    #expect(coverage.coveredTargets.first { $0.occurrenceID == "triggered" }?.phase == .triggered)
    #expect(coverage.releasedMIDINotes == [55])
}

@Test
func resolverReportsUnsupportedStaffAndOverloadedHands() {
    let unknown = makeNote(id: "unknown", midiNote: 60, hand: .unknown, staff: 3)
    let overloaded = (0 ... 5).map { index in
        makeNote(id: "right-\(index)", midiNote: 61 + index, hand: .right)
    }
    let guide = makeGuide(triggered: [unknown] + overloaded)

    let coverage = PianoDemonstrationHandTargetResolver().resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [60] + overloaded.map(\.midiNote))
    )

    #expect(coverage.coveredTargets.isEmpty)
    #expect(coverage.uncoveredKeys.first { $0.occurrenceID == "unknown" }?.reason == .unknownHand)
    #expect(coverage.uncoveredKeys.filter { $0.reason == .tooManyFingers }.count == 6)
}

@Test
func resolverReportsAChordThatExceedsOneHandSpan() {
    let guide = makeGuide(
        triggered: [
            makeNote(id: "low", midiNote: 48, hand: .left),
            makeNote(id: "high", midiNote: 60, hand: .left),
        ]
    )

    let coverage = PianoDemonstrationHandTargetResolver().resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [48, 60], spacing: 0.24)
    )

    #expect(coverage.coveredTargets.isEmpty)
    #expect(coverage.uncoveredKeys.map(\.reason) == [.spanExceeded, .spanExceeded])
}

@Test
func resolverReportsConflictingFingeringsWithoutDroppingOtherTargets() {
    let guide = makeGuide(
        triggered: [
            makeNote(id: "invalid", midiNote: 60, hand: .right, fingering: "9"),
            makeNote(id: "first", midiNote: 62, hand: .right, fingering: "1"),
            makeNote(id: "conflict", midiNote: 64, hand: .right, fingering: "1"),
        ]
    )

    let coverage = PianoDemonstrationHandTargetResolver().resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [60, 62, 64])
    )

    #expect(coverage.coveredTargets.map(\.occurrenceID) == ["invalid", "first"])
    #expect(coverage.coveredTargets.map(\.finger) == [.index, .thumb])
    #expect(coverage.uncoveredKeys.map(\.occurrenceID) == ["conflict"])
    #expect(coverage.uncoveredKeys.map(\.reason) == [.fingeringConflict])
}

@Test
func resolverReportsMissingGeometryAndReturnsEmptyWithoutGuide() {
    let resolver = PianoDemonstrationHandTargetResolver()

    #expect(
        resolver.resolve(highlightGuide: nil, keyboardGeometry: makeGeometry(notes: [60]))
            == PianoDemonstrationHandCoverage()
    )

    let missingGeometry = resolver.resolve(
        highlightGuide: makeGuide(triggered: [makeNote(id: "missing", midiNote: 60, hand: .right)]),
        keyboardGeometry: nil
    )
    #expect(missingGeometry.coveredTargets.isEmpty)
    #expect(missingGeometry.uncoveredKeys.map(\.occurrenceID) == ["missing"])
    #expect(missingGeometry.uncoveredKeys.map(\.reason) == [.missingGeometry])
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
    fingering: String? = nil,
    staff: Int? = nil
) -> PianoHighlightNote {
    let fingerings = fingering.map {
        [MusicXMLFingering(text: $0, provenance: .score)]
    } ?? []
    return PianoHighlightNote(
        occurrenceID: id,
        midiNote: midiNote,
        staff: staff ?? (hand == .left ? 2 : 1),
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

private func makeGeometry(notes: [Int], spacing: Float = 0.024) -> PianoKeyboardGeometry {
    let frame = KeyboardFrame(
        a0World: SIMD3<Float>(0, 0.5, 0),
        c8World: SIMD3<Float>(1, 0.5, 0),
        planeHeight: 0.5
    )!
    let keys = notes.enumerated().map { index, midiNote in
        PianoKeyGeometry(
            midiNote: midiNote,
            kind: .white,
            localCenter: SIMD3<Float>(Float(index) * spacing, -0.015, -0.07),
            localSize: SIMD3<Float>(0.022, 0.03, 0.14),
            surfaceLocalY: 0,
            hitCenterLocal: SIMD3<Float>(Float(index) * spacing, -0.015, -0.07),
            hitSizeLocal: SIMD3<Float>(0.022, 0.03, 0.14),
            beamFootprintCenterLocal: SIMD3<Float>(Float(index) * spacing, 0, -0.07),
            beamFootprintSizeLocal: SIMD2<Float>(0.022, 0.14)
        )
    }
    return PianoKeyboardGeometry(frame: frame, keys: keys)
}
