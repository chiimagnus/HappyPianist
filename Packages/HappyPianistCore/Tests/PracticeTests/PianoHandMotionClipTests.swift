import Foundation
@testable import Practice
import Testing

@Test
func clipRequiresTwentyOneRotationOnlyJointsAndClampsSamplesToEndpoints() throws {
    let first = frame(time: 1, x: 0.1)
    let last = frame(time: 2, x: 0.2)
    let clip = try PianoHandMotionClip(
        metadata: metadata(),
        hand: .right,
        frames: [first, last],
        coverage: [coverage(id: "c", finger: 1, onset: 1, release: 2)]
    )

    #expect(clip.frame(at: -1) == first)
    #expect(clip.frame(at: .nan) == last)
    #expect(clip.frame(at: 1.5) == first)
    #expect(clip.frame(at: 99) == last)
    #expect(clip.frames.allSatisfy { $0.jointRotations.count == PianoHandMotionClip.jointCount })
}

@Test
func clipRejectsInvalidJointDataAndCoverage() {
    #expect(throws: PianoHandMotionClip.ValidationError.invalidJointCount) {
        _ = try PianoHandMotionClip(
            metadata: metadata(),
            hand: .left,
            frames: [PianoHandMotionClip.Frame(
                timeSeconds: 0,
                rootTransform: .init(translation: .zero, rotation: [0, 0, 0, 1]),
                jointRotations: []
            )],
            coverage: [coverage(id: "c", finger: 1, onset: 0, release: 1)]
        )
    }
    #expect(throws: PianoHandMotionClip.ValidationError.invalidCoverage) {
        _ = try PianoHandMotionClip(
            metadata: metadata(),
            hand: .right,
            frames: [frame(time: 0, x: 0)],
            coverage: [coverage(id: "c", finger: 6, onset: 0, release: 1)]
        )
    }
    #expect(throws: PianoHandMotionClip.ValidationError.invalidRootTransform) {
        _ = try PianoHandMotionClip(
            metadata: metadata(),
            hand: .right,
            frames: [PianoHandMotionClip.Frame(
                timeSeconds: 0,
                rootTransform: .init(translation: .zero, rotation: [0, 0, 0, 2]),
                jointRotations: Array(
                    repeating: SIMD4<Float>(0, 0, 0, 1),
                    count: PianoHandMotionClip.jointCount
                )
            )],
            coverage: [coverage(id: "c", finger: 1, onset: 0, release: 1)]
        )
    }
}

private func metadata() -> PianoHandMotionClip.Metadata {
    PianoHandMotionClip.Metadata(
        generatorRevision: "test",
        skeletonRevision: "skeleton",
        scoreRevision: "score"
    )
}

private func frame(time: TimeInterval, x: Float) -> PianoHandMotionClip.Frame {
    PianoHandMotionClip.Frame(
        timeSeconds: time,
        rootTransform: .init(
            translation: [x, 0, 0],
            rotation: [0, 0, 0, 1]
        ),
        jointRotations: Array(
            repeating: SIMD4<Float>(0, 0, 0, 1),
            count: PianoHandMotionClip.jointCount
        )
    )
}

private func coverage(
    id: String,
    finger: Int,
    onset: TimeInterval,
    release: TimeInterval
) -> PianoHandMotionClip.Coverage {
    PianoHandMotionClip.Coverage(
        occurrenceID: id,
        finger: finger,
        onsetSeconds: onset,
        releaseSeconds: release
    )
}
