import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
private final class CapturingPracticeAudioRecognitionEffectHandler:
    PracticeSessionEffectHandlerProtocol
{
    private(set) var effects: [PracticeSessionEffect] = []

    func handle(effect: PracticeSessionEffect) {
        effects.append(effect)
    }
}

private final class FakePracticeAudioRecognitionInputServiceService:
    PracticeAudioRecognitionServiceProtocol, @unchecked Sendable
{
    struct StartCall: Equatable {
        let expectedMIDINotes: [Int]
        let generation: Int
    }

    let events: AsyncStream<DetectedNoteEvent> = AsyncStream { _ in }
    let statusUpdates: AsyncStream<PracticeAudioRecognitionStatus> = AsyncStream { _ in }

    var startCalls: [StartCall] {
        withLock { _startCalls }
    }

    var updateCalls: [StartCall] {
        withLock { _updateCalls }
    }

    var stopCallCount: Int {
        withLock { _stopCallCount }
    }

    private let lock = NSLock()
    private var _startCalls: [StartCall] = []
    private var _updateCalls: [StartCall] = []
    private var _stopCallCount = 0
    private var firstStartContinuation: CheckedContinuation<Void, Never>?
    private var shouldSuspendFirstStart = false

    init(suspendFirstStart: Bool = false) {
        shouldSuspendFirstStart = suspendFirstStart
    }

    func start(
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes _: [Int],
        generation: Int,
        suppressUntil _: Date?
    ) async throws {
        let shouldSuspend = withLock {
            _startCalls.append(StartCall(expectedMIDINotes: expectedMIDINotes, generation: generation))
            return shouldSuspendFirstStart && _startCalls.count == 1
        }
        guard shouldSuspend else { return }
        await withCheckedContinuation { continuation in
            lock.lock()
            firstStartContinuation = continuation
            lock.unlock()
        }
    }

    func updateExpectedNotes(
        _ expectedMIDINotes: [Int],
        wrongCandidateMIDINotes _: [Int],
        generation: Int
    ) {
        withLock {
            _updateCalls.append(StartCall(expectedMIDINotes: expectedMIDINotes, generation: generation))
        }
    }

    func suppressRecognition(until _: Date, generation _: Int) {}

    func stop() {
        withLock { _stopCallCount += 1 }
    }

    func resumeFirstStart() {
        let continuation = withLock {
            defer { firstStartContinuation = nil }
            return firstStartContinuation
        }
        continuation?.resume()
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
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

    service.refresh(for: guidingSnapshot(expectedMIDINotes: [60]))
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

    var snapshot = guidingSnapshot(expectedMIDINotes: [60])
    snapshot.practiceState = .ready
    inputService.refresh(for: snapshot)

    #expect(backendService.stopCallCount == 1)
    #expect(stateStore.isAudioRecognitionRunning == false)
}

@Test
@MainActor
func practiceAudioRecognitionService_lateStartRestartsWithLatestStep() async {
    let backendService = FakePracticeAudioRecognitionInputServiceService(suspendFirstStart: true)
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeAudioRecognitionEffectHandler()
    let inputService = PracticeAudioRecognitionInputService(
        service: backendService,
        accumulator: AudioStepAttemptAccumulator(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeStreams: false
    )

    inputService.refresh(for: guidingSnapshot(expectedMIDINotes: [60]))
    await waitUntil { backendService.startCalls.count == 1 }

    inputService.refresh(for: guidingSnapshot(expectedMIDINotes: [64]))
    #expect(backendService.updateCalls.last?.expectedMIDINotes == [64])

    backendService.resumeFirstStart()
    await waitUntil { backendService.startCalls.count == 2 }

    #expect(backendService.startCalls.last?.expectedMIDINotes == [64])
    #expect(backendService.startCalls.last?.generation == stateStore.audioRecognitionGeneration)
    #expect(stateStore.isAudioRecognitionRunning)
}

@Test
@MainActor
func practiceAudioRecognitionService_shutdownDoesNotRestartLateStart() async {
    let backendService = FakePracticeAudioRecognitionInputServiceService(suspendFirstStart: true)
    let stateStore = PracticeSessionStateStore()
    let effectHandler = CapturingPracticeAudioRecognitionEffectHandler()
    let inputService = PracticeAudioRecognitionInputService(
        service: backendService,
        accumulator: AudioStepAttemptAccumulator(),
        stateStore: stateStore,
        effectHandler: effectHandler,
        consumeStreams: false
    )

    inputService.refresh(for: guidingSnapshot(expectedMIDINotes: [60]))
    await waitUntil { backendService.startCalls.count == 1 }

    inputService.shutdown()
    backendService.resumeFirstStart()
    await settleTaskQueue()

    #expect(backendService.startCalls.count == 1)
    #expect(stateStore.isAudioRecognitionRunning == false)
}

@MainActor
private func guidingSnapshot(expectedMIDINotes: [Int])
    -> PracticeAudioRecognitionInputService.Snapshot
{
    PracticeAudioRecognitionInputService.Snapshot(
        practiceState: .guiding(stepIndex: 0),
        autoplayState: .off,
        isManualReplayPlaying: false,
        expectedMIDINotes: expectedMIDINotes,
        expectedRightMIDINotes: expectedMIDINotes,
        expectedLeftMIDINotes: [],
        wrongCandidateMIDINotes: [],
        handGateBoost: false,
        suppressUntil: nil
    )
}

@MainActor
private func waitUntil(
    maxIterations: Int = 100,
    condition: () -> Bool
) async {
    for _ in 0 ..< maxIterations {
        guard condition() == false else { return }
        await Task.yield()
    }
}

@MainActor
private func settleTaskQueue(iterations: Int = 8) async {
    for _ in 0 ..< iterations {
        await Task.yield()
    }
}
