import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
private final class FakeDiscoveryOrchestrator: ImprovBackendDiscoveryOrchestrating {
    func start(for _: ImprovBackendKind) {}
    func stopAll() {}
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

    private var continuation: CheckedContinuation<ImprovBackendPlaybackPlan, Error>?
    private var callWaiters: [CheckedContinuation<Bool, Never>] = []
    private var lastRequest: ImprovGenerateRequestV2?
    private var generateCallCountValue = 0

    init(kind: ImprovBackendKind, displayName: String = "Controlled") {
        self.kind = kind
        self.displayName = displayName
    }

    func generatePlaybackPlan(request: ImprovGenerateRequestV2, timeout _: Duration) async throws -> ImprovBackendPlaybackPlan {
        try Task.checkCancellation()
        lastRequest = request
        generateCallCountValue += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let waiters = callWaiters
            callWaiters.removeAll()
            for waiter in waiters {
                waiter.resume(returning: true)
            }
        }
    }

    func waitForCall() async -> Bool {
        if continuation != nil { return true }
        return await withCheckedContinuation { continuation in
            callWaiters.append(continuation)
        }
    }

    func requestSnapshot() -> ImprovGenerateRequestV2? {
        lastRequest
    }

    func generateCallCount() -> Int {
        generateCallCountValue
    }

    func resume(with plan: ImprovBackendPlaybackPlan) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: plan)
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
func continuousDuetRequestsGenerationBeforeUserReleasesKey() async {
    var nowUptime: TimeInterval = 0
    let controlClock = AIPerformanceControlClock()

    let selectedKind: ImprovBackendKind = .localRule
    let backend = ControlledBackend(kind: selectedKind)

    let aiPlaybackService = NonAdvancingPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { aiPlaybackService },
        makeExternalMIDIPlaybackService: { _ in aiPlaybackService }
    )

    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { duration in await controlClock.sleep(for: duration) },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
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
            startedVelocity: 37,
            timestamp: .init(seconds: nowUptime)
        )
    )
    nowUptime = 0.2
    await controlClock.advance()

    #expect(await backend.waitForCall())
    let request = await backend.requestSnapshot()
    #expect(request?.events.contains { $0.note == 60 && $0.velocity == 37 } == true)

    let schedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 67, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 67)),
    ]
    await backend.resume(with: .schedule(schedule, backendLatencyMS: nil))

    service.setEnabled(false)
}

@Test
@MainActor
func continuousDuetCoalescesMultipleFingersOnTheSameMIDIKey() async {
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
        observations: [
            makeTestKeyContactObservation(
                midiNote: 60,
                phase: .started,
                sequence: 1,
                timestamp: .init(seconds: 0),
                resolvedVelocity: 37
            ),
            makeTestKeyContactObservation(
                midiNote: 60,
                phase: .started,
                hand: .left,
                sequence: 2,
                timestamp: .init(seconds: 0.05),
                resolvedVelocity: 91
            ),
            makeTestKeyContactObservation(
                midiNote: 60,
                phase: .ended,
                sequence: 1,
                timestamp: .init(seconds: 0.1)
            ),
        ]
    )
    nowUptime = 0.2
    await controlClock.advance()

    #expect(await backend.waitForCall())
    let request = await backend.requestSnapshot()
    let notes = request?.events.filter { $0.note == 60 }
    #expect(notes?.count == 1)
    #expect(notes?.first?.velocity == 37)
    #expect((notes?.first?.duration ?? 0) >= 0.19)

    await backend.resume(with: .schedule([], backendLatencyMS: nil))
    service.setEnabled(false)
}

@Test
@MainActor
func continuousDuetRequestsGenerationForMIDI2Input() async {
    var nowUptime: TimeInterval = 0
    let controlClock = AIPerformanceControlClock()

    let selectedKind: ImprovBackendKind = .localRule
    let backend = ControlledBackend(kind: selectedKind)

    let aiPlaybackService = NonAdvancingPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { aiPlaybackService },
        makeExternalMIDIPlaybackService: { _ in aiPlaybackService }
    )

    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { duration in await controlClock.sleep(for: duration) },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { _ in }
    )

    let session = FakePracticeSession(settingsProvider: FakeSettingsProvider())
    service.updatePracticeSession(session)
    service.setEnabled(true)

    service.recordMIDI2EventForPhraseRecordingIfNeeded(MIDI2InputEvent(
        kind: .noteOn(note: 60, velocity16: .max),
        channel: 1,
        group: 0,
        source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: "test"),
        receivedAt: Date(timeIntervalSince1970: 0),
        receivedAtUptimeSeconds: nowUptime
    ))
    nowUptime = 0.2
    await controlClock.advance()

    #expect(await backend.waitForCall())

    await backend.resume(with: .schedule([
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 67, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 67)),
    ], backendLatencyMS: nil))

    service.setEnabled(false)
}

@Test
@MainActor
func systemPlaybackObservationDoesNotRequestContinuousDuet() async {
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

    let timestamp = PerformanceMonotonicInstant(seconds: nowUptime)
    service.recordPerformanceObservationForPhraseRecordingIfNeeded(
        PerformanceObservation(
            source: .init(
                kind: .midi1,
                id: "continuous-duet-playback",
                generation: 1,
                role: .systemPlayback
            ),
            timing: .init(
                host: timestamp,
                source: nil,
                correctedHost: timestamp,
                mapping: nil,
                provenance: .hostOnly
            ),
            event: .noteOn(note: 60, velocity: .init(midi1: 90))
        )
    )
    nowUptime = 0.3
    await controlClock.advance()
    for _ in 0 ..< 200 {
        await Task.yield()
    }

    #expect(await backend.generateCallCount() == 0)
    service.setEnabled(false)
}
