@testable import HappyPianistAVP
import MusicXML
import Practice
import simd
import Testing

@Test
func resolverUsesOnlyTheReadyPlanForHandAndFingerAssignments() {
    let guide = makeGuide(triggered: [
        makeNote(id: "right", midiNote: 60, hand: .right),
        makeNote(id: "left", midiNote: 48, hand: .left),
    ])
    let coverage = PianoDemonstrationHandTargetResolver().resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [48, 60]),
        fingeringPlan: plan([
            ("right", .right, 3),
            ("left", .left, 5),
        ])
    )

    #expect(coverage.coveredTargets(for: .right).first?.finger == .middle)
    #expect(coverage.coveredTargets(for: .left).first?.finger == .little)
    #expect(coverage.uncoveredKeys.isEmpty)
}

@Test
func resolverKeepsEveryKeyHighlightedUntilItsPlanIsReadyOrPlannable() {
    let guide = makeGuide(triggered: [
        makeNote(id: "pending", midiNote: 60, hand: .right),
        makeNote(id: "unplanned", midiNote: 62, hand: .right),
    ])
    let resolver = PianoDemonstrationHandTargetResolver()

    let pending = resolver.resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [60, 62])
    )
    let unplanned = resolver.resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [60, 62]),
        fingeringPlan: PianoFingeringPlanner.Plan(results: [
            .init(
                occurrenceID: "pending",
                resolution: .planned(hand: .right, finger: 1, source: .planned)
            ),
            .init(occurrenceID: "unplanned", resolution: .unplanned(.noSolution)),
        ])
    )

    #expect(pending.coveredTargets.isEmpty)
    #expect(pending.uncoveredKeys.map(\.reason) == [
        PianoDemonstrationHandCoverage.Reason.fingeringUnplanned,
        .fingeringUnplanned,
    ])
    #expect(unplanned.coveredTargets.map(\.occurrenceID) == ["pending"])
    #expect(unplanned.uncoveredKeys.map(\.occurrenceID) == ["unplanned"])
    #expect(unplanned.uncoveredKeys.map(\.reason) == [PianoDemonstrationHandCoverage.Reason.fingeringUnplanned])
}

@Test
func resolverPreservesHeldAndReleasedGuideFactsWithoutReplanning() {
    let guide = makeGuide(
        active: [makeNote(id: "held", midiNote: 60, hand: .right)],
        triggered: [makeNote(id: "triggered", midiNote: 64, hand: .right)],
        released: [55]
    )
    let coverage = PianoDemonstrationHandTargetResolver().resolve(
        highlightGuide: guide,
        keyboardGeometry: makeGeometry(notes: [60, 64]),
        fingeringPlan: plan([
            ("held", .right, 1),
            ("triggered", .right, 3),
        ])
    )

    #expect(coverage.coveredTargets.first { $0.occurrenceID == "held" }?.phase == .held)
    #expect(coverage.coveredTargets.first { $0.occurrenceID == "triggered" }?.phase == .triggered)
    #expect(coverage.releasedMIDINotes == [55])
}

@Test
func resolverReportsMissingGeometryBeforeItCanSubmitARigTarget() {
    let coverage = PianoDemonstrationHandTargetResolver().resolve(
        highlightGuide: makeGuide(triggered: [makeNote(id: "missing", midiNote: 60, hand: .right)]),
        keyboardGeometry: nil,
        fingeringPlan: plan([("missing", .right, 1)])
    )

    #expect(coverage.coveredTargets.isEmpty)
    #expect(coverage.uncoveredKeys.map(\.reason) == [.missingGeometry])
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

private func makeNote(id: String, midiNote: Int, hand: ScoreHand) -> PianoHighlightNote {
    PianoHighlightNote(
        occurrenceID: id,
        midiNote: midiNote,
        staff: hand == .left ? 2 : 1,
        voice: nil,
        velocity: 96,
        onTick: 0,
        offTick: 1,
        fingerings: [],
        handAssignment: ScoreHandAssignment(
            hand: hand,
            provenance: hand == .unknown ? .unresolved : .score
        )
    )
}

private func plan(
    _ assignments: [(occurrenceID: String, hand: ScoreHand, finger: Int)]
) -> PianoFingeringPlanner.Plan {
    PianoFingeringPlanner.Plan(results: assignments.map {
        .init(
            occurrenceID: $0.occurrenceID,
            resolution: .planned(hand: $0.hand, finger: $0.finger, source: .planned)
        )
    })
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
