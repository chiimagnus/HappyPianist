@testable import HappyPianistAVP
import Foundation
import MusicXML
@testable import Practice
import simd
import Testing

@Test
func playerInterpolatesTheReadyClipOnTheCurrentAudioTransport() throws {
    let timing = makeTiming(generation: 7)
    let samples = PianoHandMotionPlayer().samples(
        clipSet: .init(
            transportGeneration: 7,
            geometryCacheID: UUID(),
            clips: [try makeClip()],
            rejectedOccurrenceIDs: []
        ),
        timing: .transport(timing),
        at: .init(seconds: 0.5)
    )

    #expect(samples.count == 1)
    #expect(simd_distance(samples[0].frame.rootTransform.translation, [0.5, 0.045, -0.02]) < 0.0001)
    #expect(samples[0].activeMIDINotes == [60])
}

@Test
func playerRejectsStaleGenerationsAndFramesAfterRelease() throws {
    let clipSet = PianoDemonstrationMotionClipSet(
        transportGeneration: 7,
        geometryCacheID: UUID(),
        clips: [try makeClip()],
        rejectedOccurrenceIDs: []
    )
    let player = PianoHandMotionPlayer()

    #expect(player.samples(
        clipSet: clipSet,
        timing: .transport(makeTiming(generation: 8)),
        at: .init(seconds: 0.5)
    ).isEmpty)
    #expect(player.samples(
        clipSet: clipSet,
        timing: .transport(makeTiming(generation: 7)),
        at: .init(seconds: 1.1)
    ).isEmpty)
}

@Test
func playerTracksTheTransportRateAndFreezesWhilePaused() throws {
    let clipSet = PianoDemonstrationMotionClipSet(
        transportGeneration: 7,
        geometryCacheID: UUID(),
        clips: [try makeClip()],
        rejectedOccurrenceIDs: []
    )
    let player = PianoHandMotionPlayer()

    let fastSamples = player.samples(
        clipSet: clipSet,
        timing: .transport(makeTiming(generation: 7, playbackRate: 2)),
        at: .init(seconds: 0.25)
    )
    #expect(simd_distance(fastSamples[0].frame.rootTransform.translation, [0.5, 0.045, -0.02]) < 0.0001)

    let pausedSamples = player.samples(
        clipSet: clipSet,
        timing: .transport(makeTiming(generation: 7, isPaused: true)),
        at: .init(seconds: 0.25)
    )
    #expect(pausedSamples[0].frame.rootTransform.translation == [0, 0.045, -0.02])
}

private func makeClip() throws -> PianoHandMotionClip {
    try PianoHandMotionClip(
        metadata: .init(generatorRevision: "test", skeletonRevision: "test", scoreRevision: "test"),
        hand: .right,
        frames: [frame(time: 0, x: 0), frame(time: 1, x: 1)],
        coverage: [.init(occurrenceID: "note", finger: 2, onsetSeconds: 0, releaseSeconds: 1)]
    )
}

private func frame(time: TimeInterval, x: Float) -> PianoHandMotionClip.Frame {
    .init(
        timeSeconds: time,
        rootTransform: .init(translation: [x, 0.045, -0.02], rotation: [0, 0, 0, 1]),
        jointRotations: Array(repeating: [0, 0, 0, 1], count: PianoHandMotionClip.jointCount)
    )
}

private func makeTiming(
    generation: Int,
    playbackRate: Double = 1,
    isPaused: Bool = false
) -> PianoDemonstrationTransportTiming {
    let timeline = AutoplayPerformanceTimeline(events: [])
    let schedule = AutoplayTimelineTimeSchedule(
        timeline: timeline,
        tickToSeconds: { MusicXMLTempoMap(tempoEvents: []).timeSeconds(atTick: $0) },
        startTick: 0,
        leadInSeconds: 0
    )
    return .init(
        generation: generation,
        playbackPositionSeconds: 0,
        capturedAt: .init(seconds: 0),
        isPaused: isPaused,
        playbackRate: playbackRate,
        timeSchedule: schedule,
        contactTimeline: .init(contacts: [
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
        ]),
        guides: []
    )
}
