import Foundation
@testable import HappyPianistAVP
import simd
import Testing

@Test
func nearKeyboardWithoutExactHitProducesBoostOnly() throws {
    let gate = HandPianoActivityGate()
    let geometry = try makeKeyboardGeometry()

    let prevLocal = SIMD3<Float>(0, 0.06, -0.07)
    let currLocal = SIMD3<Float>(0, 0.02, -0.07)
    let prevWorld = transformTestPoint(geometry.frame.worldFromKeyboard, prevLocal)
    let currWorld = transformTestPoint(geometry.frame.worldFromKeyboard, currLocal)

    _ = gate.evaluate(
        fingerTips: FingerTipsSnapshot(right: HandTips(index: prevWorld)),
        keyboardGeometry: geometry,
        exactPressedNotes: [],
        at: .init(seconds: 1)
    )
    let state = gate.evaluate(
        fingerTips: FingerTipsSnapshot(right: HandTips(index: currWorld)),
        keyboardGeometry: geometry,
        exactPressedNotes: [],
        at: .init(seconds: 1.05)
    )

    #expect(state.isNearKeyboard == true)
    #expect(state.hasDownwardMotion == true)
    #expect(state.exactPressedNotes.isEmpty)
    #expect(state.confidenceBoost > 0)
}

@Test
func fingerMotionEstimatorUsesDeltaTimeAndRejectsInvalidSamples() {
    let fingerID = TrackedFingerID(hand: .right, finger: .index)
    var estimator = FingerMotionEstimator()

    let initial = estimator.estimate(
        fingerID: fingerID,
        position: SIMD3<Float>(0, 0.05, 0),
        at: .init(seconds: 1)
    )
    let moving = estimator.estimate(
        fingerID: fingerID,
        position: SIMD3<Float>(0, 0.03, 0),
        at: .init(seconds: 1.05)
    )
    let accelerating = estimator.estimate(
        fingerID: fingerID,
        position: SIMD3<Float>(0, 0.00, 0),
        at: .init(seconds: 1.10)
    )

    #expect(initial.status == .initializing)
    #expect(abs((moving.normalVelocityMetersPerSecond ?? 0) + 0.4) < 0.0001)
    #expect(abs((accelerating.normalVelocityMetersPerSecond ?? 0) + 0.6) < 0.0001)
    #expect(abs((accelerating.normalAccelerationMetersPerSecondSquared ?? 0) + 4) < 0.001)

    let stale = estimator.estimate(
        fingerID: fingerID,
        position: SIMD3<Float>(0, -0.01, 0),
        at: .init(seconds: 2)
    )
    #expect(stale.status == .invalidInterval)
    #expect(stale.normalVelocityMetersPerSecond == nil)

    let jump = estimator.estimate(
        fingerID: fingerID,
        position: SIMD3<Float>(0.3, -0.01, 0),
        at: .init(seconds: 2.05)
    )
    #expect(jump.status == .trackingJump)

    let lowConfidence = estimator.estimate(
        fingerID: fingerID,
        position: .zero,
        at: .init(seconds: 2.10),
        confidence: 0.2
    )
    #expect(lowConfidence.status == .lowConfidence)
}

@Test
@MainActor
func palmCrossingKeySurfaceCannotCreateContactOrActivity() throws {
    let geometry = try makeKeyboardGeometry()
    let palmAbove = transformTestPoint(
        geometry.frame.worldFromKeyboard,
        SIMD3<Float>(0, 0.02, -0.07)
    )
    let palmBelow = transformTestPoint(
        geometry.frame.worldFromKeyboard,
        SIMD3<Float>(0, -0.01, -0.07)
    )
    let above = FingerTipsSnapshot(right: HandTips(palm: palmAbove))
    let below = FingerTipsSnapshot(right: HandTips(palm: palmBelow))

    let virtualDetector = KeyContactDetectionService()
    let realDetector = RealPianoContactDetectionService()
    let gate = HandPianoActivityGate()
    _ = gate.evaluate(
        fingerTips: above,
        keyboardGeometry: geometry,
        exactPressedNotes: [],
        at: .init(seconds: 1)
    )

    #expect(
        virtualDetector.detect(fingerTips: below, keyboardGeometry: geometry, at: .init(seconds: 1)).isEmpty
    )
    #expect(
        realDetector.detect(fingerTips: below, keyboardGeometry: geometry, at: .init(seconds: 1)).isEmpty
    )
    #expect(
        gate.evaluate(
            fingerTips: below,
            keyboardGeometry: geometry,
            exactPressedNotes: [],
            at: .init(seconds: 1.05)
        )
            == HandGateState(
                isNearKeyboard: false,
                hasDownwardMotion: false,
                exactPressedNotes: [],
                confidenceBoost: 0
            )
    )
}

@Test
@MainActor
func exactContactAdvancesStepWithoutLegacyPressedSet() {
    let viewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        realPianoContactDetectionService: TestKeyContactDetector(results: [[
            makeTestKeyContactObservation(midiNote: 60, phase: .started),
        ]])
    )
    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 10),
        ])
    viewModel.applyKeyboardGeometry(
        makeDummyKeyboardGeometry(),
        calibration: PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0)
    )
    viewModel.startGuidingIfReady()
    _ = viewModel.handleFingerTipPositions(FingerTipsSnapshot.empty, at: .init(seconds: 1))

    #expect(viewModel.currentStepIndex == 1)
}

@Test
@MainActor
func gateInactiveStillAllowsAudioMatchedAdvance() async {
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = PracticeSessionViewModel(
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        audioRecognitionService: fakeService,
        handPianoActivityGate: HandPianoActivityGate()
    )
    viewModel.installTestPerformanceNotes(
        [
            TestScorePerformanceNote(midiNote: 60, onTick: 0),
            TestScorePerformanceNote(midiNote: 62, onTick: 10),
        ])
    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    let generation = fakeService.startCalls.first?.generation ?? 0

    fakeService.emitEvidence(
        makeTargetAudioEvidence(
            midiNote: 60,
            confidence: 0.95,
            onsetScore: 0.9,
            isOnset: true,
            timestamp: .init(seconds: 1),
            generation: generation
        )
    )
    await settleTaskQueue()

    #expect(viewModel.currentStepIndex == 1)
}

private func makeKeyboardGeometry() throws -> PianoKeyboardGeometry {
    let frame = try #require(
        KeyboardFrame(
            a0World: SIMD3<Float>(0, 0, 0),
            c8World: SIMD3<Float>(1, 0, 0),
            planeHeight: 0
        )
    )
    let key = PianoKeyGeometry(
        midiNote: 60,
        kind: .white,
        localCenter: SIMD3<Float>(0, -0.015, -0.07),
        localSize: SIMD3<Float>(0.02, 0.03, 0.14),
        surfaceLocalY: 0,
        hitCenterLocal: SIMD3<Float>(0, -0.015, -0.07),
        hitSizeLocal: SIMD3<Float>(0.02, 0.03, 0.14),
        beamFootprintCenterLocal: SIMD3<Float>(0, 0, -0.07),
        beamFootprintSizeLocal: SIMD2<Float>(0.018, 0.11)
    )
    return PianoKeyboardGeometry(frame: frame, keys: [key])
}

private func makeDummyKeyboardGeometry() -> PianoKeyboardGeometry {
    let frame = KeyboardFrame(
        a0World: SIMD3<Float>(0.0, 0.0, 0.0),
        c8World: SIMD3<Float>(1.0, 0.0, 0.0),
        planeHeight: 0.0
    )!
    return PianoKeyboardGeometry(frame: frame, keys: [])
}

private func settleTaskQueue(iterations: Int = 4) async {
    for _ in 0 ..< iterations {
        await Task.yield()
    }
}

private func transformTestPoint(
    _ matrix: simd_float4x4,
    _ point: SIMD3<Float>
) -> SIMD3<Float> {
    let value = simd_mul(matrix, SIMD4<Float>(point, 1))
    return SIMD3<Float>(value.x, value.y, value.z)
}

private final class NoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        at _: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        testAttemptOutcome(matched: false)
    }

    func reset() {}
}

private final class AlwaysMatchChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        at _: PerformanceMonotonicInstant
    ) -> StepAttemptMatchResult {
        testAttemptOutcome(matched: true)
    }

    func reset() {}
}
