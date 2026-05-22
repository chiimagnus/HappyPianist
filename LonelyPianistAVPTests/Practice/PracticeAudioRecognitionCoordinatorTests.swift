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

private final class FakePracticeAudioRecognitionInputServiceService: PracticeAudioRecognitionServiceProtocol {
    let events: AsyncStream<DetectedNoteEvent> = AsyncStream { _ in }
    let statusUpdates: AsyncStream<PracticeAudioRecognitionStatus> = AsyncStream { _ in }
    let debugSnapshots: AsyncStream<PracticeAudioRecognitionDebugSnapshot> = AsyncStream { _ in }

    var startCallCount: Int { withLock { _startCallCount } }
    var stopCallCount: Int { withLock { _stopCallCount } }

    private let lock = NSLock()
    private var _startCallCount = 0
    private var _stopCallCount = 0

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func start(
        expectedMIDINotes _: [Int],
        wrongCandidateMIDINotes _: [Int],
        generation _: Int,
        suppressUntil _: Date?
    ) async throws {
        withLock { _startCallCount += 1 }
    }

    func updateExpectedNotes(_: [Int], wrongCandidateMIDINotes _: [Int], generation _: Int) {}
    func configureDetectorMode(_: PracticeAudioRecognitionDetectorMode, profile _: HarmonicTemplateTuningProfile) {}
    func suppressRecognition(until _: Date, generation _: Int) {}

    func stop() {
        withLock { _stopCallCount += 1 }
    }
}

@Test
@MainActor
func practiceAudioRecognitionService_serviceNilHasNoSideEffects() async {
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeAudioRecognitionEffectHandler()
    let service = PracticeAudioRecognitionInputService(
        service: nil,
        accumulator: AudioStepAttemptAccumulator(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeStreams: false
    )

    service.refresh(
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
            suppressUntil: nil
        )
    )
    service.stop()
    service.shutdown()
    await Task.yield()

    #expect(stateStore.isAudioRecognitionRunning == false)
}

@Test
@MainActor
func practiceAudioRecognitionService_shutdownIsIdempotent() {
    let backendService = FakePracticeAudioRecognitionInputServiceService()
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeAudioRecognitionEffectHandler()
    let inputService = PracticeAudioRecognitionInputService(
        service: backendService,
        accumulator: AudioStepAttemptAccumulator(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeStreams: false
    )

    inputService.shutdown()
    inputService.shutdown()

    #expect(backendService.stopCallCount == 1)
}

@Test
@MainActor
func practiceAudioRecognitionService_refreshOutsideGuidingStopsService() {
    let backendService = FakePracticeAudioRecognitionInputServiceService()
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeAudioRecognitionEffectHandler()
    stateStore.isAudioRecognitionRunning = true
    let inputService = PracticeAudioRecognitionInputService(
        service: backendService,
        accumulator: AudioStepAttemptAccumulator(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeStreams: false
    )

    inputService.refresh(
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
            suppressUntil: nil
        )
    )

    #expect(backendService.stopCallCount == 1)
    #expect(stateStore.isAudioRecognitionRunning == false)
}
