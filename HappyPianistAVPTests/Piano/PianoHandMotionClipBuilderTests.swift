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
            contact(id: "right-next", midiNote: 62, onset: 0.4),
        ]),
        fingeringPlan: PianoFingeringPlanner.Plan(results: [
            .init(occurrenceID: "left", resolution: .planned(hand: .left, finger: 5, source: .planned)),
            .init(occurrenceID: "right", resolution: .planned(hand: .right, finger: 1, source: .planned)),
            .init(occurrenceID: "right-next", resolution: .planned(hand: .right, finger: 2, source: .planned)),
        ]),
        keyboardLayout: .init(keys: [
            .init(midiNote: 48, contactPositionLocal: [-0.10, 0, -0.07]),
            .init(midiNote: 60, contactPositionLocal: [0.10, 0, -0.07]),
            .init(midiNote: 62, contactPositionLocal: [0.12, 0, -0.07]),
        ]),
        scoreRevision: "test-score"
    )

    let result = try await PianoHandMotionClipBuilder().buildOffMain(input: input)

    #expect(result.rejectedOccurrenceIDs.isEmpty)
    #expect(result.clips.map(\.hand) == [.left, .right])
    #expect(result.clips[0].coverage.map(\.occurrenceID) == ["left"])
    #expect(result.clips[1].coverage.map(\.finger) == [1, 2])
    #expect(result.clips[1].frames.map(\.timeSeconds) == [0.2, 0.4])
    #expect(result.clips.allSatisfy { clip in
        clip.frames.allSatisfy { $0.jointRotations.count == PianoHandMotionClip.jointCount }
    })
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
            .init(midiNote: 60, contactPositionLocal: [0.10, 0, -0.07]),
            .init(midiNote: 60, contactPositionLocal: [0.12, 0, -0.07]),
        ]),
        scoreRevision: "test-score"
    ))

    #expect(result.clips.isEmpty)
    #expect(result.rejectedOccurrenceIDs == ["ambiguous"])
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
