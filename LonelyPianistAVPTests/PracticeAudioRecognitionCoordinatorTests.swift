import Foundation
@testable import LonelyPianistAVP
import Testing

@MainActor
private final class CapturingPracticeAudioRecognitionEffectHandler: PracticeSessionEffectHandlerProtocol {
    private(set) var effects: [PracticeSessionEffect] = []

    func handle(effect: PracticeSessionEffect) {
        effects.append(effect)
    }
}

@MainActor
private final class FakePracticeAudioRecognitionCoordinatorService: PracticeAudioRecognitionServiceProtocol {
    let events: AsyncStream<DetectedNoteEvent> = AsyncStream { _ in }
    let statusUpdates: AsyncStream<PracticeAudioRecognitionStatus> = AsyncStream { _ in }
    let debugSnapshots: AsyncStream<PracticeAudioRecognitionDebugSnapshot> = AsyncStream { _ in }

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start(
        expectedMIDINotes _: [Int],
        wrongCandidateMIDINotes _: [Int],
        generation _: Int,
        suppressUntil _: Date?
    ) async throws {
        startCallCount += 1
    }

    func updateExpectedNotes(_: [Int], wrongCandidateMIDINotes _: [Int], generation _: Int) {}
    func configureDetectorMode(_: PracticeAudioRecognitionDetectorMode, profile _: HarmonicTemplateTuningProfile) {}
    func suppressRecognition(until _: Date, generation _: Int) {}

    func stop() {
        stopCallCount += 1
    }
}

@Test
@MainActor
func practiceAudioRecognitionCoordinator_serviceNilHasNoSideEffects() async {
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeAudioRecognitionEffectHandler()
    let coordinator = PracticeAudioRecognitionCoordinator(
        service: nil,
        accumulator: AudioStepAttemptAccumulator(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeStreams: false
    )

    coordinator.refresh(
        for: .init(
            practiceState: .guiding(stepIndex: 0),
            autoplayState: .off,
            isManualReplayPlaying: false,
            isAudioRecognitionEnabled: true,
            expectedMIDINotes: [60],
            expectedRightMIDINotes: [],
            expectedLeftMIDINotes: [],
            wrongCandidateMIDINotes: [],
            handGateBoost: false,
            isHandSeparatedStepMatchingEnabled: false,
            suppressUntil: nil
        )
    )
    coordinator.stop()
    coordinator.shutdown()
    await Task.yield()

    #expect(stateStore.isAudioRecognitionRunning == false)
}

@Test
@MainActor
func practiceAudioRecognitionCoordinator_shutdownIsIdempotent() {
    let service = FakePracticeAudioRecognitionCoordinatorService()
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeAudioRecognitionEffectHandler()
    let coordinator = PracticeAudioRecognitionCoordinator(
        service: service,
        accumulator: AudioStepAttemptAccumulator(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeStreams: false
    )

    coordinator.shutdown()
    coordinator.shutdown()

    #expect(service.stopCallCount == 1)
}

@Test
@MainActor
func practiceAudioRecognitionCoordinator_refreshOutsideGuidingStopsService() {
    let service = FakePracticeAudioRecognitionCoordinatorService()
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeAudioRecognitionEffectHandler()
    stateStore.isAudioRecognitionRunning = true
    let coordinator = PracticeAudioRecognitionCoordinator(
        service: service,
        accumulator: AudioStepAttemptAccumulator(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeStreams: false
    )

    coordinator.refresh(
        for: .init(
            practiceState: .ready,
            autoplayState: .off,
            isManualReplayPlaying: false,
            isAudioRecognitionEnabled: true,
            expectedMIDINotes: [60],
            expectedRightMIDINotes: [],
            expectedLeftMIDINotes: [],
            wrongCandidateMIDINotes: [],
            handGateBoost: false,
            isHandSeparatedStepMatchingEnabled: false,
            suppressUntil: nil
        )
    )

    #expect(service.stopCallCount == 1)
    #expect(stateStore.isAudioRecognitionRunning == false)
}
