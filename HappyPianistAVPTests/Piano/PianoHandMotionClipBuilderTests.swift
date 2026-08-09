@testable import HappyPianistAVP
import Foundation
import MusicXML
@testable import Practice
import simd
import Testing

@Test
func builderCreatesOneDeterministicClipPerPlannedHandOffMain() async throws {
    let input = PianoHandMotionClipBuilder.Input(
        contacts: PianoKeyContactTimeline(contacts: [
            contact(id: "left", midiNote: 48, onset: 0.1),
            contact(id: "right", midiNote: 60, onset: 0.2),
            contact(id: "right-chord", midiNote: 61, onset: 0.2),
            contact(id: "right-next", midiNote: 62, onset: 0.4),
        ]),
        fingeringPlan: PianoFingeringPlanner.Plan(results: [
            .init(occurrenceID: "left", resolution: .planned(hand: .left, finger: 5, source: .planned)),
            .init(occurrenceID: "right", resolution: .planned(hand: .right, finger: 1, source: .planned)),
            .init(occurrenceID: "right-chord", resolution: .planned(hand: .right, finger: 2, source: .planned)),
            .init(occurrenceID: "right-next", resolution: .planned(hand: .right, finger: 2, source: .planned)),
        ]),
        keyboardLayout: .init(keys: [
            key(midiNote: 48, position: [-0.10, 0, -0.07]),
            key(midiNote: 60, position: [0.10, 0, -0.07]),
            key(midiNote: 61, position: [0.11, 0, -0.07]),
            key(midiNote: 62, position: [0.12, 0, -0.07]),
        ]),
        scoreRevision: "test-score"
    )

    let result = try await PianoHandMotionClipBuilder().buildOffMain(input: input)

    #expect(result.rejectedOccurrenceIDs.isEmpty)
    #expect(result.clips.map(\.hand) == [.left, .right])
    #expect(result.clips[0].coverage.map(\.occurrenceID) == ["left"])
    #expect(result.clips[1].coverage.map(\.finger) == [1, 2, 2])
    #expect(result.clips[1].frames.map(\.timeSeconds).contains(0.2))
    #expect(result.clips[1].frames.map(\.timeSeconds).contains(0.4))
    #expect(result.clips[1].frames.allSatisfy {
        $0.rootTransform.rotation != SIMD4<Float>(0, 0, 0, 1)
    })
    #expect(result.clips[1].frames[0].jointRotations[1].z != 0)
    #expect(result.clips.allSatisfy { clip in
        clip.frames.allSatisfy { $0.jointRotations.count == PianoHandMotionClip.jointCount }
    })
}

@Test
func builderRejectsAnImpossibleHandPoseInsteadOfClampingIt() throws {
    let result = try PianoHandMotionClipBuilder().build(input: .init(
        contacts: PianoKeyContactTimeline(contacts: [
            contact(id: "low", midiNote: 48, onset: 0),
            contact(id: "high", midiNote: 72, onset: 0),
        ]),
        fingeringPlan: PianoFingeringPlanner.Plan(results: [
            .init(occurrenceID: "low", resolution: .planned(hand: .right, finger: 1, source: .planned)),
            .init(occurrenceID: "high", resolution: .planned(hand: .right, finger: 2, source: .planned)),
        ]),
        keyboardLayout: .init(keys: [
            key(midiNote: 48, position: [-0.20, 0, -0.07]),
            key(midiNote: 72, position: [0.20, 0, -0.07]),
        ]),
        scoreRevision: "test-score"
    ))

    #expect(result.clips.isEmpty)
    #expect(result.rejectedOccurrenceIDs == ["high", "low"])
}

@Test
func builderRejectsAHandPoseThatWouldExceedJointVelocityLimit() throws {
    let result = try PianoHandMotionClipBuilder().build(input: .init(
        contacts: PianoKeyContactTimeline(contacts: [
            contact(id: "first-thumb", midiNote: 60, onset: 0),
            contact(id: "first-index", midiNote: 62, onset: 0),
            contact(id: "next-thumb", midiNote: 61, onset: 0.001),
        ]),
        fingeringPlan: PianoFingeringPlanner.Plan(results: [
            .init(occurrenceID: "first-thumb", resolution: .planned(hand: .right, finger: 1, source: .planned)),
            .init(occurrenceID: "first-index", resolution: .planned(hand: .right, finger: 2, source: .planned)),
            .init(occurrenceID: "next-thumb", resolution: .planned(hand: .right, finger: 1, source: .planned)),
        ]),
        keyboardLayout: .init(keys: [
            key(midiNote: 60, position: [0, 0, -0.07]),
            key(midiNote: 61, position: [-0.10, 0, -0.07]),
            key(midiNote: 62, position: [0.08, 0, -0.07]),
        ]),
        scoreRevision: "test-score"
    ))

    #expect(result.clips.isEmpty)
    #expect(result.rejectedOccurrenceIDs == ["first-index", "first-thumb", "next-thumb"])
}

@Test
func builderRejectsWristTravelThatCannotFinishBeforeTheNextOnset() throws {
    let result = try PianoHandMotionClipBuilder().build(input: .init(
        contacts: PianoKeyContactTimeline(contacts: [
            contact(id: "near", midiNote: 60, onset: 0),
            contact(id: "far", midiNote: 72, onset: 0.1),
        ]),
        fingeringPlan: PianoFingeringPlanner.Plan(results: [
            .init(occurrenceID: "near", resolution: .planned(hand: .right, finger: 1, source: .planned)),
            .init(occurrenceID: "far", resolution: .planned(hand: .right, finger: 1, source: .planned)),
        ]),
        keyboardLayout: .init(keys: [
            key(midiNote: 60, position: [0, 0, -0.07]),
            key(midiNote: 72, position: [0.60, 0, -0.07]),
        ]),
        scoreRevision: "test-score"
    ))

    #expect(result.clips.isEmpty)
    #expect(result.rejectedOccurrenceIDs == ["far", "near"])
}

@Test
func builderReturnsUnplayableOccurrencesInsteadOfInventingGeometry() throws {
    let result = try PianoHandMotionClipBuilder().build(input: .init(
        contacts: PianoKeyContactTimeline(contacts: [contact(id: "missing", midiNote: 60, onset: 0)]),
        fingeringPlan: PianoFingeringPlanner.Plan(results: [
            .init(occurrenceID: "missing", resolution: .planned(hand: .right, finger: 1, source: .planned)),
        ]),
        keyboardLayout: .init(keys: []),
        scoreRevision: "test-score"
    ))

    #expect(result.clips.isEmpty)
    #expect(result.rejectedOccurrenceIDs == ["missing"])
}

@Test
func builderRejectsAmbiguousKeyboardGeometry() throws {
    let result = try PianoHandMotionClipBuilder().build(input: .init(
        contacts: PianoKeyContactTimeline(contacts: [contact(id: "ambiguous", midiNote: 60, onset: 0)]),
        fingeringPlan: PianoFingeringPlanner.Plan(results: [
            .init(occurrenceID: "ambiguous", resolution: .planned(hand: .right, finger: 1, source: .planned)),
        ]),
        keyboardLayout: .init(keys: [
            key(midiNote: 60, position: [0.10, 0, -0.07]),
            key(midiNote: 60, position: [0.12, 0, -0.07]),
        ]),
        scoreRevision: "test-score"
    ))

    #expect(result.clips.isEmpty)
    #expect(result.rejectedOccurrenceIDs == ["ambiguous"])
}

@Test
func builderRejectsAChordWhoseFingerCapsulesIntersect() throws {
    let result = try PianoHandMotionClipBuilder().build(input: .init(
        contacts: PianoKeyContactTimeline(contacts: [
            contact(id: "first", midiNote: 60, onset: 0),
            contact(id: "second", midiNote: 61, onset: 0),
        ]),
        fingeringPlan: PianoFingeringPlanner.Plan(results: [
            .init(occurrenceID: "first", resolution: .planned(hand: .right, finger: 2, source: .planned)),
            .init(occurrenceID: "second", resolution: .planned(hand: .right, finger: 3, source: .planned)),
        ]),
        keyboardLayout: .init(keys: [
            key(midiNote: 60, position: [0, 0, -0.07], topSurfaceSizeLocal: [0.002, 0.160]),
            key(midiNote: 61, position: [0.001, 0, -0.07], topSurfaceSizeLocal: [0.002, 0.160]),
        ]),
        scoreRevision: "test-score"
    ))

    #expect(result.clips.isEmpty)
    #expect(result.rejectedOccurrenceIDs == ["first", "second"])
}

@Test
func builderRejectsAContactThatPenetratesPastTheKeySurfaceAllowance() throws {
    let result = try PianoHandMotionClipBuilder().build(input: .init(
        contacts: PianoKeyContactTimeline(contacts: [contact(id: "sunken", midiNote: 60, onset: 0)]),
        fingeringPlan: PianoFingeringPlanner.Plan(results: [
            .init(occurrenceID: "sunken", resolution: .planned(hand: .right, finger: 2, source: .planned)),
        ]),
        keyboardLayout: .init(keys: [
            key(midiNote: 60, position: [0, -0.004, -0.07], surfaceLocalY: 0),
        ]),
        scoreRevision: "test-score"
    ))

    #expect(result.clips.isEmpty)
    #expect(result.rejectedOccurrenceIDs == ["sunken"])
}

@Test
func builderLiftsThePalmByOnlyTheRequiredKeyboardClearance() throws {
    let result = try PianoHandMotionClipBuilder().build(input: .init(
        contacts: PianoKeyContactTimeline(contacts: [contact(id: "target", midiNote: 60, onset: 0)]),
        fingeringPlan: PianoFingeringPlanner.Plan(results: [
            .init(occurrenceID: "target", resolution: .planned(hand: .right, finger: 2, source: .planned)),
        ]),
        keyboardLayout: .init(keys: [
            key(midiNote: 60, position: [0, 0, -0.07], topSurfaceSizeLocal: [0.010, 0.010]),
            key(midiNote: 61, position: [0.015, 0.031, -0.030], topSurfaceSizeLocal: [0.010, 0.010]),
        ]),
        scoreRevision: "test-score"
    ))

    #expect(result.rejectedOccurrenceIDs.isEmpty)
    #expect(result.clips[0].frames[0].rootTransform.translation.y > 0.045)
}

private func contact(
    id: String,
    midiNote: Int,
    onset: TimeInterval
) -> PianoKeyContactTimeline.Contact {
    PianoKeyContactTimeline.Contact(
        occurrenceID: id,
        midiNote: midiNote,
        staff: midiNote < 60 ? 2 : 1,
        handAssignment: ScoreHandAssignment(hand: .unknown, provenance: .unresolved),
        fingerings: [],
        velocity: 96,
        guideID: nil,
        stepIndex: nil,
        carriedIn: false,
        timing: .scheduled(onsetSeconds: onset, releaseSeconds: onset + 0.1)
    )
}

private func key(
    midiNote: Int,
    position: SIMD3<Float>,
    surfaceLocalY: Float? = nil,
    topSurfaceSizeLocal: SIMD2<Float> = [0.022, 0.160]
) -> PianoHandMotionClipBuilder.KeyboardLayout.Key {
    .init(
        midiNote: midiNote,
        contactPositionLocal: position,
        surfaceLocalY: surfaceLocalY ?? position.y,
        topSurfaceSizeLocal: topSurfaceSizeLocal
    )
}
