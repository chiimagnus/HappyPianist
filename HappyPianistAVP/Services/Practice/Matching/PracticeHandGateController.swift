import Foundation
import simd

@MainActor
final class PracticeHandGateController {
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
        fingerTips: FingerTipsSnapshot,
        keyboardGeometry: PianoKeyboardGeometry,
        exactPressedNotes: Set<Int>,
        at timestamp: PerformanceMonotonicInstant
    ) {
        stateStore.handGateState = activityGate.evaluate(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            exactPressedNotes: exactPressedNotes,
            at: timestamp
        )
    }

    func registerChordAttemptIfNeeded(
        observations: [PianoKeyContactObservation],
        at timestamp: PerformanceMonotonicInstant,
        practiceHandMode: PracticeHandMode
    ) {
        let evidence = HandSeparatedNoteEvidence(startedContacts: observations)
        guard evidence.isEmpty == false else { return }
        guard stateStore.acceptsPracticeAttempts else { return }
        guard case .guiding = stateStore.state else { return }
        guard stateStore.autoplayState == .off else { return }
        guard stateStore.isManualReplayPlaying == false else { return }
        guard stateStore.steps.indices.contains(stateStore.currentStepIndex) else { return }

        let currentStep = stateStore.steps[stateStore.currentStepIndex]
        let expectedNotes = filteredNotesForPracticeHandMode(
            currentStep.notes,
            mode: practiceHandMode
        )
        let expectedMIDINotes = Set(expectedNotes.map(\.midiNote)).sorted()
        guard expectedMIDINotes.isEmpty == false else { return }

        let expectedByHand = uniqueMIDINotesByHand(notes: expectedNotes)
        let outcome = chordAttemptAccumulator.registerHandSeparated(
            evidence: evidence,
            expectedRightNotes: expectedByHand.right,
            expectedLeftNotes: expectedByHand.left,
            expectedUnassignedNotes: expectedByHand.unknown,
            tolerance: stateStore.noteMatchTolerance,
            at: timestamp
        )

        effectHandler?.handle(effect: .attemptEvaluated(outcome))
        if outcome.isMatched {
            effectHandler?.handle(effect: .advanceToNextStep)
        }
    }

    private func filteredNotesForPracticeHandMode(
        _ notes: [PracticeStepNote],
        mode: PracticeHandMode
    ) -> [PracticeStepNote] {
        if mode == .both { return notes }
        return notes.filter { mode.allows(hand: $0.hand) }
    }
}
