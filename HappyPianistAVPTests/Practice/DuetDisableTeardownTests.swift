import Foundation
@testable import HappyPianistAVP
import Testing

actor AIPerformanceControlClock {
    private let ticks: AsyncStream<Void>
    private let tickContinuation: AsyncStream<Void>.Continuation

    init() {
        (ticks, tickContinuation) = AsyncStream.makeStream()
    }

    func sleep(for _: Duration) async {
        var iterator = ticks.makeAsyncIterator()
        _ = await iterator.next()
    }

    func advance() {
        tickContinuation.yield()
    }
}

@MainActor
private final class FakeDiscoveryOrchestrator: ImprovBackendDiscoveryOrchestrating {
    func start(for _: ImprovBackendKind) {}
    func stopAll() {}
}

@MainActor
private final class MutableBackendKind {
    var value: ImprovBackendKind

    init(_ value: ImprovBackendKind) {
        self.value = value
    }
}

@MainActor
private final class FakePracticeSession: AIPerformancePracticeSessionProtocol {
    let settingsProvider: any PracticeSessionSettingsProviderProtocol

    init(settingsProvider: any PracticeSessionSettingsProviderProtocol) {
        self.settingsProvider = settingsProvider
    }

    func refreshAudioRecognitionForCurrentState() {}
}

private actor ControlledBackend: ImprovBackendProtocol {
    nonisolated let kind: ImprovBackendKind
    nonisolated let displayName: String

    private var continuations: [CheckedContinuation<ImprovBackendPlaybackPlan, Error>] = []
    private var calls = 0
    private var callWaiters: [(minimumCount: Int, continuation: CheckedContinuation<Bool, Never>)] = []

    init(kind: ImprovBackendKind, displayName: String = "Controlled") {
        self.kind = kind
        self.displayName = displayName
    }

    func generatePlaybackPlan(request _: ImprovGenerateRequestV2, timeout _: Duration) async throws -> ImprovBackendPlaybackPlan {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            calls += 1
            continuations.append(continuation)
            let readyWaiters = callWaiters.filter { $0.minimumCount <= calls }
            callWaiters.removeAll { $0.minimumCount <= calls }
            for waiter in readyWaiters {
                waiter.continuation.resume(returning: true)
            }
        }
    }

    func waitForCall(minimumCount: Int = 1) async -> Bool {
        if calls >= minimumCount { return true }
        return await withCheckedContinuation { continuation in
            callWaiters.append((minimumCount, continuation))
        }
    }

    func resume(with plan: ImprovBackendPlaybackPlan) {
        guard continuations.isEmpty == false else { return }
        let continuation = continuations.removeFirst()
        continuation.resume(returning: plan)
    }

    func generateCallCount() -> Int {
        calls
    }
}

@MainActor
private final class NonAdvancingPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    func warmUp() throws {}
    func stop(resetCommands _: [PerformanceTransportCommand]) {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}

@MainActor
private struct FakeSettingsProvider: PracticeSessionSettingsProviderProtocol {
    var manualAdvanceMode: ManualAdvanceMode {
        .step
    }

    var practiceHandMode: PracticeHandMode {
        .both
    }

    var soundRoutingSettings: PracticeSoundRoutingSettings {
        PracticeSoundRoutingSettings(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false)
    }
}

@Test
@MainActor
func releasedServiceStopsItsControlLoop() async {
    weak var releasedService: AIPerformanceService?
    let playbackService = NonAdvancingPlaybackService()
    let factory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )

    do {
        let service = AIPerformanceService(
            sleepFor: { _ in await Task.yield() },
            discoveryOrchestrator: FakeDiscoveryOrchestrator(),
            backendRegistry: .init(),
            selectedBackendKind: { .localRule },
            aiPlaybackServiceFactory: { factory },
            onStateChanged: { _ in }
        )
        releasedService = service
        service.setEnabled(true)
        await Task.yield()
    }

    for _ in 0 ..< 20 where releasedService != nil {
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(releasedService == nil)
}

@Test
@MainActor
func disablingServiceDropsLateBackendResponses() async {
    var nowUptime: TimeInterval = 0
    let controlClock = AIPerformanceControlClock()

    let selectedKind: ImprovBackendKind = .localRule
    let backend = ControlledBackend(kind: selectedKind)

    let aiPlaybackService = NonAdvancingPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { aiPlaybackService },
        makeExternalMIDIPlaybackService: { _ in aiPlaybackService }
    )

    var didEnqueueAnySchedule = false
    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { duration in await controlClock.sleep(for: duration) },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { state in
            didEnqueueAnySchedule = didEnqueueAnySchedule || state.latestSchedule.isEmpty == false
        }
    )

    let session = FakePracticeSession(settingsProvider: FakeSettingsProvider())
    service.updatePracticeSession(session)
    service.setEnabled(true)

    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        observations: makeTestKeyContactObservations(
            activeMIDINotes: [60],
            startedMIDINotes: [60],
            timestamp: .init(seconds: nowUptime)
        )
    )
    nowUptime = 0.2
    await controlClock.advance()

    #expect(await backend.waitForCall())

    service.setEnabled(false)
    service.setEnabled(true)

    let schedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 60)),
    ]
    await backend.resume(with: .schedule(schedule, backendLatencyMS: nil))

    for _ in 0 ..< 200 {
        await Task.yield()
    }

    #expect(didEnqueueAnySchedule == false)

    service.setEnabled(false)
}

@Test
@MainActor
func newInputDropsStaleContinuousResponse() async {
    var nowUptime: TimeInterval = 0
    let controlClock = AIPerformanceControlClock()
    let selectedKind: ImprovBackendKind = .networkBonjourHTTPAriaV2
    let backend = ControlledBackend(kind: selectedKind)
    let playbackService = NonAdvancingPlaybackService()
    let factory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )
    var enqueuedSchedule = false
    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { duration in await controlClock.sleep(for: duration) },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { factory },
        onStateChanged: { enqueuedSchedule = enqueuedSchedule || $0.latestSchedule.isEmpty == false }
    )
    let session = FakePracticeSession(settingsProvider: FakeSettingsProvider())
    service.updatePracticeSession(session)
    service.setEnabled(true)
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        observations: makeTestKeyContactObservations(
            activeMIDINotes: [60],
            startedMIDINotes: [60],
            timestamp: .init(seconds: 0)
        )
    )
    nowUptime = 0.2
    await controlClock.advance()
    #expect(await backend.waitForCall())

    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        observations: makeTestKeyContactObservations(
            activeMIDINotes: [60, 62],
            startedMIDINotes: [62],
            timestamp: .init(seconds: nowUptime)
        )
    )
    nowUptime = 0.4
    await controlClock.advance()
    #expect(await backend.waitForCall(minimumCount: 2))

    await backend.resume(with: .schedule([
        PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 72)),
    ], backendLatencyMS: nil))

    for _ in 0 ..< 200 {
        await Task.yield()
    }
    #expect(enqueuedSchedule == false)

    await backend.resume(with: .schedule([
        PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 74, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 74)),
    ], backendLatencyMS: nil))
    for _ in 0 ..< 200 {
        await Task.yield()
    }
    #expect(enqueuedSchedule)
    service.setEnabled(false)
}

@Test
@MainActor
func changingBackendDoesNotWaitForSuspendedOldBackend() async {
    var nowUptime: TimeInterval = 0
    let controlClock = AIPerformanceControlClock()
    let selectedKind = MutableBackendKind(.localRule)
    let oldBackend = ControlledBackend(kind: .localRule)
    let newBackend = ControlledBackend(kind: .networkBonjourHTTPAriaV2)
    let playbackService = NonAdvancingPlaybackService()
    let factory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )
    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { duration in await controlClock.sleep(for: duration) },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [oldBackend, newBackend]),
        selectedBackendKind: { selectedKind.value },
        aiPlaybackServiceFactory: { factory },
        onStateChanged: { _ in }
    )
    let session = FakePracticeSession(settingsProvider: FakeSettingsProvider())
    service.updatePracticeSession(session)
    service.setEnabled(true)
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        observations: makeTestKeyContactObservations(
            activeMIDINotes: [60],
            startedMIDINotes: [60],
            timestamp: .init(seconds: 0)
        )
    )
    nowUptime = 0.2
    await controlClock.advance()
    #expect(await oldBackend.waitForCall())

    selectedKind.value = .networkBonjourHTTPAriaV2
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        observations: makeTestKeyContactObservations(
            activeMIDINotes: [60, 64],
            startedMIDINotes: [64],
            timestamp: .init(seconds: nowUptime)
        )
    )
    nowUptime = 0.4
    await controlClock.advance()
    #expect(await newBackend.waitForCall())

    await newBackend.resume(with: .schedule([], backendLatencyMS: nil))
    await oldBackend.resume(with: .schedule([], backendLatencyMS: nil))
    service.setEnabled(false)
}

@Test
@MainActor
func replacingPracticeSessionInvalidatesOldResponse() async {
    var nowUptime: TimeInterval = 0
    let controlClock = AIPerformanceControlClock()
    let selectedKind: ImprovBackendKind = .networkBonjourHTTPAriaV2
    let backend = ControlledBackend(kind: selectedKind)
    let playbackService = NonAdvancingPlaybackService()
    let factory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )
    var enqueuedSchedule = false
    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { duration in await controlClock.sleep(for: duration) },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { factory },
        onStateChanged: { enqueuedSchedule = enqueuedSchedule || $0.latestSchedule.isEmpty == false }
    )
    let firstSession = FakePracticeSession(settingsProvider: FakeSettingsProvider())
    let replacementSession = FakePracticeSession(settingsProvider: FakeSettingsProvider())
    service.updatePracticeSession(firstSession)
    service.setEnabled(true)
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        observations: makeTestKeyContactObservations(
            activeMIDINotes: [60],
            startedMIDINotes: [60],
            timestamp: .init(seconds: 0)
        )
    )
    nowUptime = 0.2
    await controlClock.advance()
    #expect(await backend.waitForCall())

    service.updatePracticeSession(replacementSession)
    await backend.resume(with: .schedule([
        PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 72)),
    ], backendLatencyMS: nil))
    for _ in 0 ..< 200 {
        await Task.yield()
    }

    #expect(enqueuedSchedule == false)
    service.setEnabled(false)
}

@Test
@MainActor
func silentContextDropsLateContinuousResponse() async {
    var nowUptime: TimeInterval = 0
    let controlClock = AIPerformanceControlClock()
    let selectedKind: ImprovBackendKind = .localRule
    let backend = ControlledBackend(kind: selectedKind)
    let playbackService = NonAdvancingPlaybackService()
    let factory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )
    var enqueuedSchedule = false
    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { duration in await controlClock.sleep(for: duration) },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { factory },
        onStateChanged: { enqueuedSchedule = enqueuedSchedule || $0.latestSchedule.isEmpty == false }
    )
    let session = FakePracticeSession(settingsProvider: FakeSettingsProvider())
    service.updatePracticeSession(session)
    service.setEnabled(true)
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        observations: makeTestKeyContactObservations(
            activeMIDINotes: [60],
            startedMIDINotes: [60],
            timestamp: .init(seconds: 0)
        )
    )
    nowUptime = 0.2
    await controlClock.advance()
    #expect(await backend.waitForCall())

    nowUptime = 2.0
    await backend.resume(with: .schedule([
        PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 72)),
    ], backendLatencyMS: nil))

    for _ in 0 ..< 200 {
        await Task.yield()
    }
    #expect(enqueuedSchedule == false)
    service.setEnabled(false)
}

@Test
@MainActor
func disablingAndReenablingKeepsNewRequestTracked() async {
    var nowUptime: TimeInterval = 0
    let controlClock = AIPerformanceControlClock()
    let selectedKind: ImprovBackendKind = .localRule
    let backend = ControlledBackend(kind: selectedKind)
    let playbackService = NonAdvancingPlaybackService()
    let factory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )
    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { duration in await controlClock.sleep(for: duration) },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { factory },
        onStateChanged: { _ in }
    )
    let session = FakePracticeSession(settingsProvider: FakeSettingsProvider())
    service.updatePracticeSession(session)
    service.setEnabled(true)
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        observations: makeTestKeyContactObservations(
            activeMIDINotes: [60],
            startedMIDINotes: [60],
            timestamp: .init(seconds: 0)
        )
    )
    nowUptime = 0.2
    await controlClock.advance()
    #expect(await backend.waitForCall())

    service.setEnabled(false)
    service.setEnabled(true)
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        observations: makeTestKeyContactObservations(
            activeMIDINotes: [64],
            startedMIDINotes: [64],
            timestamp: .init(seconds: nowUptime)
        )
    )
    nowUptime = 0.4
    await controlClock.advance()
    #expect(await backend.waitForCall(minimumCount: 2))

    await backend.resume(with: .schedule([], backendLatencyMS: nil))
    for _ in 0 ..< 200 {
        await Task.yield()
    }
    #expect(await backend.generateCallCount() == 2)

    await backend.resume(with: .schedule([], backendLatencyMS: nil))
    service.setEnabled(false)
}
