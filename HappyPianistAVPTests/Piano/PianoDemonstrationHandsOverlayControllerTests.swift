@testable import HappyPianistAVP
import Foundation
import MusicXML
@testable import Practice
import RealityKit
import Testing

@MainActor
@Test
func hidingTeacherHandsImmediatelyRestoresKeyboardHighlights() async throws {
    let rig = try await PackagedPianoDemonstrationHandRigLoader().load(hand: .right)
    let controller = PianoDemonstrationHandsOverlayController(
        preloadedRigs: [.right: rig],
        performanceClock: .init(now: { .init(seconds: 0.1) })
    )
    let frame = try #require(KeyboardFrame(
        a0World: .zero,
        c8World: [1, 0, 0],
        planeHeight: 0
    ))
    let geometry = PianoKeyboardGeometry(frame: frame, keys: [])
    let timing = makeTransportTiming()
    let clipSet = try makeMotionClipSet()

    #expect(controller.update(
        isEnabled: true,
        motionClipSet: clipSet,
        timing: .transport(timing),
        keyboardGeometry: geometry,
        reduceMotion: false,
        content: nil
    ) == [60])
    #expect(rig.rootEntity.isEnabled)

    #expect(controller.update(
        isEnabled: true,
        motionClipSet: clipSet,
        timing: .transport(timing),
        keyboardGeometry: geometry,
        reduceMotion: true,
        content: nil
    ).isEmpty)
    #expect(rig.rootEntity.isEnabled == false)
}

private func makeTransportTiming() -> PianoDemonstrationTransportTiming {
    let timeline = AutoplayPerformanceTimeline(events: [])
    let schedule = AutoplayTimelineTimeSchedule(
        timeline: timeline,
        tickToSeconds: { MusicXMLTempoMap(tempoEvents: []).timeSeconds(atTick: $0) },
        startTick: 0,
        leadInSeconds: 0
    )
    let contacts = PianoKeyContactTimeline(contacts: [
        .init(
            occurrenceID: "note",
            midiNote: 60,
            staff: 1,
            handAssignment: .init(hand: .right, provenance: .score),
            fingerings: [],
            velocity: 96,
            guideID: nil,
            stepIndex: nil,
            carriedIn: false,
            timing: .scheduled(onsetSeconds: 0, releaseSeconds: 1)
        ),
    ])
    return .init(
        generation: 1,
        playbackPositionSeconds: 0,
        capturedAt: .init(seconds: 0),
        isPaused: false,
        playbackRate: 1,
        timeSchedule: schedule,
        contactTimeline: contacts,
        guides: []
    )
}

private func makeMotionClipSet() throws -> PianoDemonstrationMotionClipSet {
    let clip = try PianoHandMotionClip(
        metadata: .init(generatorRevision: "test", skeletonRevision: "test", scoreRevision: "test"),
        hand: .right,
        frames: [
            .init(
                timeSeconds: 0,
                rootTransform: .init(translation: [0, 0.045, -0.02], rotation: [0, 0, 0, 1]),
                jointRotations: Array(repeating: [0, 0, 0, 1], count: PianoHandMotionClip.jointCount)
            ),
        ],
        coverage: [.init(occurrenceID: "note", finger: 2, onsetSeconds: 0, releaseSeconds: 1)]
    )
    return .init(
        transportGeneration: 1,
        geometryCacheID: UUID(),
        clips: [clip],
        rejectedOccurrenceIDs: []
    )
}
