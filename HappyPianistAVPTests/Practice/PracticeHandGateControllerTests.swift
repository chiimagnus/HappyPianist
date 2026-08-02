import Foundation
import Diagnostics
import MusicXML
import Practice
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
        at _: PerformanceMonotonicInstant
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
    let effectHandler = CapturingEffectHandler()
    let controller = PracticeHandGateController(
        activityGate: HandPianoActivityGate(),
        chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
        stateStore: store,
        effectHandler: effectHandler
    )

    controller.registerChordAttemptIfNeeded(
        observations: [makeTestKeyContactObservation(midiNote: 60, phase: .started)],
        at: .init(seconds: 1),
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

    controller.registerChordAttemptIfNeeded(
        observations: [makeTestKeyContactObservation(midiNote: 60, phase: .started)],
        at: .init(seconds: 1),
        practiceHandMode: .both
    )

    #expect(effectHandler.effects.isEmpty)
}

@Test
@MainActor
func uncertainSpatialCandidatesDoNotAdvancePractice() {
    for candidate in [PianoKeyCandidate.ambiguous([59, 60]), .unknown] {
        let store = PracticeSessionStateStore()
        store.steps = [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)])]
        store.state = .guiding(stepIndex: 0)
        store.acceptsPracticeAttempts = true

        let effectHandler = CapturingEffectHandler()
        let controller = PracticeHandGateController(
            activityGate: HandPianoActivityGate(),
            chordAttemptAccumulator: AlwaysMatchChordAttemptAccumulator(),
            stateStore: store,
            effectHandler: effectHandler
        )
        let observation = PianoKeyContactObservation(
            id: PianoKeyContactID(finger: TrackedFingerID(hand: .right, finger: .index), sequence: 1),
            phase: .started,
            keyCandidate: candidate,
            timestamp: .init(seconds: 1),
            confidence: 0.5,
            worldPosition: .zero,
            planeDistanceMeters: 0,
            normalVelocityMetersPerSecond: nil,
            resolvedVelocity: nil,
            calibrationID: UUID()
        )

        controller.registerChordAttemptIfNeeded(
            observations: [observation],
            at: .init(seconds: 1),
            practiceHandMode: .both
        )

        #expect(effectHandler.effects == [.attemptEvaluated(.insufficientEvidence)])
    }
}
