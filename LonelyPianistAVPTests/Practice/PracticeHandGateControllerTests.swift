import Foundation
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

@Test
@MainActor
func chordMatchAdvancesToNextStepViaEffect() {
    let store = PracticeSessionStateStore()
    store.steps = [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
    ]
    store.currentStepIndex = 0
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

    #expect(effectHandler.effects == [.advanceToNextStep])
}
