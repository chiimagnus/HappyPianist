import Foundation
@testable import HappyPianistAVP
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
    ) -> StepAttemptMatchResult {
        testAttemptOutcome(matched: true)
    }

    func reset() {}
}

@Test
@MainActor
func chordMatchAdvancesToNextStepViaEffect() {
    let store = PracticeSessionStateStore()
    store.steps = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]),
    ]
    store.currentStepIndex = 0
    store.state = .guiding(stepIndex: 0)
    store.acceptsPracticeAttempts = true
    store.autoplayState = .off
    store.isManualReplayPlaying = false
    store.noteMatchTolerance = 1

    let effectHandler = CapturingEffectHandler()
    let controller = PracticeHandGateController(
        activityGate: HandPianoActivityGate(),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        stateStore: store,
        effectHandler: effectHandler
    )

    controller.registerChordAttemptIfNeeded(
        pressedNotes: [60],
        at: .now,
        practiceHandMode: .both
    )

    #expect(effectHandler.effects.count == 2)
    if case .attemptEvaluated(.matched) = effectHandler.effects.first {
        // Expected typed attempt evidence before advancement.
    } else {
        Issue.record("Expected a matched attempt effect")
    }
    #expect(effectHandler.effects.last == .advanceToNextStep)
}

@Test
@MainActor
func chordMatchDoesNotAdvanceWhileReady() {
    let store = PracticeSessionStateStore()
    store.steps = [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)])]
    store.currentStepIndex = 0
    store.state = .ready
    store.acceptsPracticeAttempts = true

    let effectHandler = CapturingEffectHandler()
    let controller = PracticeHandGateController(
        activityGate: HandPianoActivityGate(),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        stateStore: store,
        effectHandler: effectHandler
    )

    controller.registerChordAttemptIfNeeded(pressedNotes: [60], at: .now, practiceHandMode: .both)

    #expect(effectHandler.effects.isEmpty)
}
