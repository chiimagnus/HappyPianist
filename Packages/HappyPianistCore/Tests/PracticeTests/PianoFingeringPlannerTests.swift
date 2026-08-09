import Foundation
import MusicXML
@testable import Practice
import Testing

@Test
func plannerUsesDeterministicDPForScaleCrossoverAndPhraseContinuity() throws {
    let contacts = PianoKeyContactTimeline(contacts: [
        contact(id: "c", midi: 60, onset: 0),
        contact(id: "d", midi: 62, onset: 0.20),
        contact(id: "e", midi: 64, onset: 0.40),
        contact(id: "f", midi: 65, onset: 0.60),
        contact(id: "g", midi: 67, onset: 0.80),
    ])
    let layout = layout([
        (60, .white, 0),
        (62, .white, 0.024),
        (64, .white, 0.048),
        (65, .white, 0.072),
        (67, .white, 0.096),
    ])

    let plan = try PianoFingeringPlanner().plan(contacts: contacts, keyboardLayout: layout)

    #expect(plan.results.map(\.occurrenceID) == ["c", "d", "e", "f", "g"])
    #expect(plan.results.map(finger) == [1, 2, 3, 1, 2])
    #expect(plan.results.map(\.resolution) == [
        .planned(hand: .right, finger: 1, source: .planned),
        .planned(hand: .right, finger: 2, source: .planned),
        .planned(hand: .right, finger: 3, source: .planned),
        .planned(hand: .right, finger: 1, source: .planned),
        .planned(hand: .right, finger: 2, source: .planned),
    ])
}

@Test
func plannerMotionLimitsRejectNonFiniteValuesConservatively() {
    let limits = PianoFingeringPlanner.MotionLimits(
        maximumHandSpanMeters: .nan,
        maximumHandTravelMetersPerSecond: .infinity
    )

    #expect(limits.maximumHandSpanMeters == 0)
    #expect(limits.maximumHandTravelMetersPerSecond == 0)
}

@Test
func plannerUsesAttackIntervalForAdjacentNoteHandoffs() throws {
    let plan = try PianoFingeringPlanner().plan(
        contacts: PianoKeyContactTimeline(contacts: [
            contact(id: "held", midi: 60, onset: 0, release: 0.5),
            contact(id: "next", midi: 67, onset: 0.5),
        ]),
        keyboardLayout: layout([
            (60, .white, 0),
            (67, .white, 0.096),
        ])
    )

    #expect(plan.results.allSatisfy { result in
        if case .planned = result.resolution { return true }
        return false
    })
}

@Test
func plannerPreservesManualFingeringAndRewardsRepeatedNotes() throws {
    let contacts = PianoKeyContactTimeline(contacts: [
        contact(id: "c", midi: 60, onset: 0),
        contact(id: "e", midi: 64, onset: 0, fingerings: [fingering("3")]),
        contact(id: "repeat-e", midi: 64, onset: 0.20),
    ])
    let plan = try PianoFingeringPlanner().plan(
        contacts: contacts,
        keyboardLayout: layout([
            (60, .white, 0),
            (64, .white, 0.048),
        ])
    )

    #expect(resolution(try #require(plan.result(forOccurrenceID: "e"))) == .planned(
        hand: .right,
        finger: 3,
        source: .score
    ))
    #expect(finger(try #require(plan.result(forOccurrenceID: "repeat-e"))) == 3)
}

@Test
func plannerAvoidsThumbOnBlackKeysAndUsesStaffOnlyForUnknownHands() throws {
    let black = contact(id: "black", midi: 61, onset: 0)
    let staffFallback = contact(id: "left", midi: 48, hand: .unknown, staff: 2, onset: 0)
    let plan = try PianoFingeringPlanner().plan(
        contacts: PianoKeyContactTimeline(contacts: [black, staffFallback]),
        keyboardLayout: layout([
            (48, .white, -0.20),
            (61, .black, 0.01),
        ])
    )

    #expect(finger(try #require(plan.result(forOccurrenceID: "black"))) != 1)
    #expect(resolution(try #require(plan.result(forOccurrenceID: "left"))) == .planned(
        hand: .left,
        finger: 1,
        source: .planned
    ))
}

@Test
func plannerStartsACarriedInOccurrenceAtANewPhraseBoundary() throws {
    let plan = try PianoFingeringPlanner().plan(
        contacts: PianoKeyContactTimeline(contacts: [
            contact(id: "before", midi: 60, onset: 0, release: 0.05),
            contact(id: "carried", midi: 72, onset: 0.06, carriedIn: true),
        ]),
        keyboardLayout: layout([
            (60, .white, 0),
            (72, .white, 0.50),
        ])
    )

    #expect(finger(try #require(plan.result(forOccurrenceID: "before"))) != nil)
    #expect(finger(try #require(plan.result(forOccurrenceID: "carried"))) != nil)
}

@Test
func plannerMakesConflictingOrUnsupportedScoreFingeringsExplicitlyUnplanned() throws {
    let duplicateA = contact(id: "duplicate-a", midi: 65, onset: 0)
    let duplicateB = contact(id: "duplicate-b", midi: 65, onset: 0)
    let invalid = contact(id: "invalid", midi: 60, onset: 0.2, fingerings: [fingering("x")])
    let ambiguous = contact(id: "ambiguous", midi: 61, onset: 0.4, fingerings: [fingering("2"), fingering("3")])
    let incompatibleHand = contact(
        id: "incompatible-hand",
        midi: 62,
        onset: 0.6,
        fingerings: [MusicXMLFingering(text: "2", hand: .left, provenance: .score)]
    )
    let plan = try PianoFingeringPlanner().plan(
        contacts: PianoKeyContactTimeline(contacts: [
            duplicateA,
            duplicateB,
            invalid,
            ambiguous,
            incompatibleHand,
        ]),
        keyboardLayout: layout([
            (60, .white, 0),
            (61, .black, 0.01),
            (62, .white, 0.024),
            (65, .white, 0.072),
        ])
    )

    #expect(resolution(try #require(plan.result(forOccurrenceID: "duplicate-a"))) == .unplanned(.fingeringConflict))
    #expect(resolution(try #require(plan.result(forOccurrenceID: "duplicate-b"))) == .unplanned(.fingeringConflict))
    #expect(resolution(try #require(plan.result(forOccurrenceID: "invalid"))) == .unplanned(.invalidManualFingering))
    #expect(resolution(try #require(plan.result(forOccurrenceID: "ambiguous"))) == .unplanned(.ambiguousManualFingering))
    #expect(resolution(try #require(plan.result(forOccurrenceID: "incompatible-hand"))) == .unplanned(.manualHandConflict))
}

@Test
func plannerMarksOversizedContactLinesAsBudgetExceeded() throws {
    let contacts = PianoKeyContactTimeline(contacts: (0 ... 512).map {
        contact(id: "budget-\($0)", midi: 60, onset: TimeInterval($0))
    })
    let plan = try PianoFingeringPlanner().plan(
        contacts: contacts,
        keyboardLayout: layout([(60, .white, 0)])
    )

    #expect(plan.results.count == 513)
    #expect(plan.results.allSatisfy { resolution($0) == .unplanned(.budgetExceeded) })
}

@Test
func plannerMakesMissingGeometrySpansAndImpossibleTravelExplicitlyUnplanned() throws {
    let missingKey = contact(id: "missing", midi: 61, onset: 0)
    let wideLow = contact(id: "wide-low", midi: 60, onset: 0.20)
    let wideHigh = contact(id: "wide-high", midi: 67, onset: 0.20)
    let jumpStart = contact(id: "jump-start", midi: 62, onset: 0.50, release: 0.55)
    let jumpEnd = contact(id: "jump-end", midi: 69, onset: 0.56)
    let plan = try PianoFingeringPlanner().plan(
        contacts: PianoKeyContactTimeline(contacts: [missingKey, wideLow, wideHigh, jumpStart, jumpEnd]),
        keyboardLayout: layout([
            (60, .white, 0),
            (62, .white, 0),
            (67, .white, 0.30),
            (69, .white, 0.50),
        ])
    )

    #expect(resolution(try #require(plan.result(forOccurrenceID: "missing"))) == .unplanned(.missingKey))
    #expect(resolution(try #require(plan.result(forOccurrenceID: "wide-low"))) == .unplanned(.spanExceeded))
    #expect(resolution(try #require(plan.result(forOccurrenceID: "wide-high"))) == .unplanned(.spanExceeded))
    #expect(resolution(try #require(plan.result(forOccurrenceID: "jump-start"))) == .unplanned(.noSolution))
    #expect(resolution(try #require(plan.result(forOccurrenceID: "jump-end"))) == .unplanned(.noSolution))
}

@Test
func plannerRejectsCancelledOffMainPlanningBeforeItStarts() async {
    let planner = PianoFingeringPlanner()
    let contacts = PianoKeyContactTimeline(contacts: [contact(id: "c", midi: 60, onset: 0)])
    let keyboardLayout = layout([(60, .white, 0)])
    let task = Task<PianoFingeringPlanner.Plan, Error> {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await planner.planOffMain(contacts: contacts, keyboardLayout: keyboardLayout)
    }

    await #expect(throws: CancellationError.self) {
        _ = try await task.value
    }
}

private func contact(
    id: String,
    midi: Int,
    hand: ScoreHand = .right,
    staff: Int = 1,
    onset: TimeInterval,
    release: TimeInterval? = nil,
    carriedIn: Bool = false,
    fingerings: [MusicXMLFingering] = []
) -> PianoKeyContactTimeline.Contact {
    PianoKeyContactTimeline.Contact(
        occurrenceID: id,
        midiNote: midi,
        staff: staff,
        handAssignment: ScoreHandAssignment(
            hand: hand,
            provenance: hand == .unknown ? .unresolved : .score
        ),
        fingerings: fingerings,
        velocity: 96,
        guideID: nil,
        stepIndex: nil,
        carriedIn: carriedIn,
        timing: .scheduled(onsetSeconds: onset, releaseSeconds: release ?? onset + 0.05)
    )
}

private func fingering(_ text: String) -> MusicXMLFingering {
    MusicXMLFingering(text: text, provenance: .score)
}

private func layout(
    _ keys: [(midi: Int, kind: PianoFingeringKeyboardLayout.KeyKind, x: Double)]
) -> PianoFingeringKeyboardLayout {
    PianoFingeringKeyboardLayout(keys: keys.map {
        .init(midiNote: $0.midi, kind: $0.kind, localX: $0.x)
    })
}

private func resolution(_ result: PianoFingeringPlanner.Result) -> PianoFingeringPlanner.Resolution {
    result.resolution
}

private func finger(_ result: PianoFingeringPlanner.Result) -> Int? {
    guard case let .planned(_, finger, _) = result.resolution else { return nil }
    return finger
}
