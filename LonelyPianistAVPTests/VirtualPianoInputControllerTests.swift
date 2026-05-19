import Foundation
import simd
@testable import LonelyPianistAVP
import Testing

@MainActor
private final class CapturingEffectHandler: PracticeSessionEffectHandlerProtocol {
    private(set) var effects: [PracticeSessionEffect] = []

    func handle(effect: PracticeSessionEffect) {
        effects.append(effect)
    }
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

    func registerHandSeparated(
        pressedNotes _: Set<Int>,
        expectedRightNotes _: [Int],
        expectedLeftNotes _: [Int],
        tolerance _: Int,
        at _: Date
    ) -> Bool {
        true
    }

    func reset() {}
}

@MainActor
private final class FakeKeyContactDetector: KeyContactDetectingProtocol {
    var resultToReturn: KeyContactResult

    init(resultToReturn: KeyContactResult) {
        self.resultToReturn = resultToReturn
    }

    func reset() {}

    func detect(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry
    ) -> KeyContactResult {
        resultToReturn
    }
}

@MainActor
private final class FakeSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var startedLiveNotes: [Set<Int>] = []
    private(set) var stoppedLiveNotes: [Set<Int>] = []

    func warmUp() throws {}
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval { 0 }
    func playOneShot(midiNotes _: [Int], durationSeconds _: TimeInterval) throws {}

    func startLiveNotes(midiNotes: Set<Int>) throws {
        startedLiveNotes.append(midiNotes)
    }

    func stopLiveNotes(midiNotes: Set<Int>) {
        stoppedLiveNotes.append(midiNotes)
    }

    func stopAllLiveNotes() {}
}

private func makeMinimalKeyboardGeometry() -> PianoKeyboardGeometry {
    let frame = KeyboardFrame(worldFromKeyboard: matrix_identity_float4x4)
    let key = PianoKeyGeometry(
        midiNote: 60,
        kind: .white,
        localCenter: .zero,
        localSize: SIMD3<Float>(1, 0.02, 0.2),
        surfaceLocalY: 0,
        hitCenterLocal: .zero,
        hitSizeLocal: SIMD3<Float>(1, 0.02, 0.2),
        beamFootprintCenterLocal: .zero,
        beamFootprintSizeLocal: SIMD2<Float>(1, 0.2)
    )
    return PianoKeyboardGeometry(frame: frame, keys: [key])
}

@Test
@MainActor
func virtualPianoPlaysLiveNotesWhenNotSuppressed() {
    let store = PracticeSessionStateStore()
    store.autoplayState = .off
    store.isManualReplayPlaying = false
    store.steps = [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])]
    store.currentStepIndex = 0

    let effectHandler = CapturingEffectHandler()
    let handGateController = PracticeHandGateController(
        activityGate: HandPianoActivityGate(),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        stateStore: store,
        effectHandler: effectHandler
    )

    let detector = FakeKeyContactDetector(
        resultToReturn: KeyContactResult(down: [60], started: [60], ended: [61])
    )
    let sequencer = FakeSequencerPlaybackService()
    let controller = VirtualPianoInputController(
        detector: detector,
        sequencerPlaybackService: sequencer,
        stateStore: store,
        handGateController: handGateController
    )

    _ = controller.handleFingerTips(
        ["finger": .zero],
        keyboardGeometry: makeMinimalKeyboardGeometry(),
        at: .now,
        isHandSeparatedStepMatchingEnabled: false
    )

    #expect(sequencer.startedLiveNotes == [[60]])
    #expect(sequencer.stoppedLiveNotes == [[61]])
    #expect(effectHandler.effects.contains(.advanceToNextStep))
}

@Test
@MainActor
func virtualPianoDoesNotPlayLiveNotesDuringAutoplay() {
    let store = PracticeSessionStateStore()
    store.autoplayState = .playing
    store.isManualReplayPlaying = false

    let effectHandler = CapturingEffectHandler()
    let handGateController = PracticeHandGateController(
        activityGate: HandPianoActivityGate(),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        stateStore: store,
        effectHandler: effectHandler
    )

    let detector = FakeKeyContactDetector(
        resultToReturn: KeyContactResult(down: [60], started: [60], ended: [61])
    )
    let sequencer = FakeSequencerPlaybackService()
    let controller = VirtualPianoInputController(
        detector: detector,
        sequencerPlaybackService: sequencer,
        stateStore: store,
        handGateController: handGateController
    )

    _ = controller.handleFingerTips(
        ["finger": .zero],
        keyboardGeometry: makeMinimalKeyboardGeometry(),
        at: .now,
        isHandSeparatedStepMatchingEnabled: false
    )

    #expect(sequencer.startedLiveNotes.isEmpty)
    #expect(sequencer.stoppedLiveNotes.isEmpty)
}

