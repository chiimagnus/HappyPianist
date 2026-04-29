import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

@Test
func nearKeyboardWithoutExactHitProducesBoostOnly() throws {
    let gate = HandPianoActivityGate()
    let geometry = try makeKeyboardGeometry()

    let prevLocal = SIMD3<Float>(0, 0.06, -0.07)
    let currLocal = SIMD3<Float>(0, 0.02, -0.07)
    let prevWorld = PressDetectionService.transformPoint(geometry.frame.worldFromKeyboard, prevLocal)
    let currWorld = PressDetectionService.transformPoint(geometry.frame.worldFromKeyboard, currLocal)

    _ = gate.evaluate(
        fingerTips: ["index": prevWorld],
        keyboardGeometry: geometry,
        exactPressedNotes: []
    )
    let state = gate.evaluate(
        fingerTips: ["index": currWorld],
        keyboardGeometry: geometry,
        exactPressedNotes: []
    )

    #expect(state.isNearKeyboard == true)
    #expect(state.hasDownwardMotion == true)
    #expect(state.exactPressedNotes.isEmpty)
    #expect(state.confidenceBoost > 0)
}

@Test
@MainActor
func exactHitFallbackStillAdvancesStep() {
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: ConstantPressDetectionService(pressedNotes: [60]),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 10, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.applyKeyboardGeometry(
        makeDummyKeyboardGeometry(),
        calibration: PianoCalibration(a0: .zero, c8: SIMD3<Float>(1, 0, 0), planeHeight: 0)
    )
    viewModel.startGuidingIfReady()
    _ = viewModel.handleFingerTipPositions(["finger": .zero], at: Date())

    #expect(viewModel.currentStepIndex == 1)
}

@Test
@MainActor
func gateInactiveStillAllowsAudioMatchedAdvance() async {
    UserDefaults.standard.set(true, forKey: "practiceAudioRecognitionEnabled")
    let fakeService = FakePracticeAudioRecognitionService()
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NoopPressDetectionService(),
        chordAttemptAccumulator: NoopChordAttemptAccumulator(),
        sleeper: TaskSleeper(),
        audioRecognitionService: fakeService,
        handPianoActivityGate: HandPianoActivityGate()
    )
    viewModel.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 10, notes: [PracticeStepNote(midiNote: 62, staff: nil)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    viewModel.startGuidingIfReady()
    await settleTaskQueue()
    let generation = fakeService.startCalls.first?.generation ?? 0

    fakeService.emitEvent(
        DetectedNoteEvent(
            midiNote: 60,
            confidence: 0.95,
            onsetScore: 0.9,
            isOnset: true,
            timestamp: Date().addingTimeInterval(0.9),
            generation: generation,
            source: .audio
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

private struct NoopPressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        []
    }
}

private struct ConstantPressDetectionService: PressDetectionServiceProtocol {
    let pressedNotes: Set<Int>

    init(pressedNotes: Set<Int>) {
        self.pressedNotes = pressedNotes
    }

    init(pressedNotes: [Int]) {
        self.pressedNotes = Set(pressedNotes)
    }

    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        pressedNotes
    }
}

private final class NoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        tolerance _: Int,
        at _: Date
    ) -> Bool {
        false
    }

    func reset() {}
}

private final class AlwaysMatchChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        tolerance _: Int,
        at _: Date
    ) -> Bool {
        true
    }

    func reset() {}
}
