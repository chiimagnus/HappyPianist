import Foundation
import simd

@MainActor
final class PracticeHandGateController: PracticeSessionLifecycleProtocol {
    private let activityGate: HandPianoActivityGate
    private let chordAttemptAccumulator: ChordAttemptAccumulatorProtocol
    private let stateStore: PracticeSessionStateStore
    private weak var effectHandler: (any PracticeSessionEffectHandlerProtocol)?
    private var hasShutdown = false

    init(
        activityGate: HandPianoActivityGate,
        chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
        stateStore: PracticeSessionStateStore,
        effectHandler: any PracticeSessionEffectHandlerProtocol
    ) {
        self.activityGate = activityGate
        self.chordAttemptAccumulator = chordAttemptAccumulator
        self.stateStore = stateStore
        self.effectHandler = effectHandler
    }

    func shutdown() {
        guard hasShutdown == false else { return }
        hasShutdown = true
        reset()
    }

    func reset() {
        activityGate.reset()
        chordAttemptAccumulator.reset()
        stateStore.handGateState = HandGateState(
            isNearKeyboard: false,
            hasDownwardMotion: false,
            exactPressedNotes: [],
            confidenceBoost: 0
        )
    }

    func updateHandGateState(
        fingerTips: [String: SIMD3<Float>],
        keyboardGeometry: PianoKeyboardGeometry,
        exactPressedNotes: Set<Int>
    ) {
        stateStore.handGateState = activityGate.evaluate(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            exactPressedNotes: exactPressedNotes
        )
    }

    func registerChordAttemptIfNeeded(
        pressedNotes: Set<Int>,
        at timestamp: Date,
        isHandSeparatedStepMatchingEnabled: Bool
    ) {
        guard pressedNotes.isEmpty == false else { return }
        guard stateStore.autoplayState == .off else { return }
        guard stateStore.isManualReplayPlaying == false else { return }
        guard stateStore.state != .completed else { return }
        guard stateStore.steps.indices.contains(stateStore.currentStepIndex) else { return }

        let currentStep = stateStore.steps[stateStore.currentStepIndex]
        let expectedMIDINotes = Set(currentStep.notes.map(\.midiNote)).sorted()
        guard expectedMIDINotes.isEmpty == false else { return }

        let matched: Bool
        if isHandSeparatedStepMatchingEnabled {
            let expectedByHand = uniqueMIDINotesByHand(in: currentStep)
            matched = chordAttemptAccumulator.registerHandSeparated(
                pressedNotes: pressedNotes,
                expectedRightNotes: expectedByHand.right,
                expectedLeftNotes: expectedByHand.left,
                tolerance: stateStore.noteMatchTolerance,
                at: timestamp
            )
        } else {
            matched = chordAttemptAccumulator.register(
                pressedNotes: pressedNotes,
                expectedNotes: expectedMIDINotes,
                tolerance: stateStore.noteMatchTolerance,
                at: timestamp
            )
        }

        if matched {
            effectHandler?.handle(effect: .advanceToNextStep)
        }
    }
}

