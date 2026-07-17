import Foundation
@testable import HappyPianistAVP
import Testing

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
    var autoplayState: PracticeSessionAutoplayState = .off
    var isManualReplayPlaying: Bool = false
    var currentStep: PracticeStep?
    var autoplayTimeline: AutoplayPerformanceTimeline = .empty
    var tempoMap: MusicXMLTempoMap = .init(tempoEvents: [])
    var pedalTimeline: MusicXMLPedalTimeline?
    let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol
    let settingsProvider: any PracticeSessionSettingsProviderProtocol

    init(
        sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol,
        settingsProvider: any PracticeSessionSettingsProviderProtocol
    ) {
        self.sequencerPlaybackService = sequencerPlaybackService
        self.settingsProvider = settingsProvider
    }

    func stopVirtualPianoInput() {}
    func stopAudioRecognition() {}
    func prepareAudioRecognitionSuppressWindowForPlayback() -> Date {
        .now
    }

    func refreshAudioRecognitionForCurrentState() {}
}

private actor ControlledBackend: ImprovBackendProtocol {
    nonisolated let kind: ImprovBackendKind
    nonisolated let displayName: String

    private var continuations: [CheckedContinuation<ImprovBackendPlaybackPlan, Error>] = []
    private var calls = 0

    init(kind: ImprovBackendKind, displayName: String = "Controlled") {
        self.kind = kind
        self.displayName = displayName
    }

    func generatePlaybackPlan(request _: ImprovGenerateRequestV2, timeout _: Duration) async throws -> ImprovBackendPlaybackPlan {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            calls += 1
            continuations.append(continuation)
        }
    }

    func waitForCall(minimumCount: Int = 1, timeout: Duration = .seconds(2)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if continuations.count >= minimumCount { return true }
            // ponytail: 1 ms polling keeps this test helper deterministic without a bespoke test clock.
            try? await Task.sleep(for: .milliseconds(1))
        }
        return continuations.count >= minimumCount
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
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(noteOns _: [PracticeOneShotNoteOn], durationSeconds _: TimeInterval) throws {}
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
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
        sleepFor: { _ in },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { state in
            didEnqueueAnySchedule = didEnqueueAnySchedule || state.latestSchedule.isEmpty == false
        }
    )

    let practicePlaybackService = NonAdvancingPlaybackService()
    let session = FakePracticeSession(
        sequencerPlaybackService: practicePlaybackService,
        settingsProvider: FakeSettingsProvider()
    )
    service.updatePracticeSession(session)
    service.setEnabled(true)

    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [60], started: [60], ended: []),
        nowUptimeSeconds: nowUptime
    )
    nowUptime = 0.2

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
func newInputReevaluatesContinuousResponseAgainstLatestContext() async {
    var nowUptime: TimeInterval = 0
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
        sleepFor: { _ in },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { factory },
        onStateChanged: { enqueuedSchedule = enqueuedSchedule || $0.latestSchedule.isEmpty == false }
    )
    let session = FakePracticeSession(sequencerPlaybackService: playbackService, settingsProvider: FakeSettingsProvider())
    service.updatePracticeSession(session)
    service.setEnabled(true)
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [60], started: [60], ended: []),
        nowUptimeSeconds: 0
    )
    nowUptime = 0.2
    #expect(await backend.waitForCall())

    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [60, 62], started: [62], ended: []),
        nowUptimeSeconds: nowUptime
    )
    nowUptime = 0.3
    await backend.resume(with: .schedule([
        PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 72)),
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
        sleepFor: { _ in },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [oldBackend, newBackend]),
        selectedBackendKind: { selectedKind.value },
        aiPlaybackServiceFactory: { factory },
        onStateChanged: { _ in }
    )
    let session = FakePracticeSession(sequencerPlaybackService: playbackService, settingsProvider: FakeSettingsProvider())
    service.updatePracticeSession(session)
    service.setEnabled(true)
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [60], started: [60], ended: []),
        nowUptimeSeconds: 0
    )
    nowUptime = 0.2
    #expect(await oldBackend.waitForCall())

    selectedKind.value = .networkBonjourHTTPAriaV2
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [60, 64], started: [64], ended: []),
        nowUptimeSeconds: nowUptime
    )
    nowUptime = 0.4
    #expect(await newBackend.waitForCall())

    await newBackend.resume(with: .schedule([], backendLatencyMS: nil))
    await oldBackend.resume(with: .schedule([], backendLatencyMS: nil))
    service.setEnabled(false)
}

@Test
@MainActor
func replacingPracticeSessionInvalidatesOldResponse() async {
    var nowUptime: TimeInterval = 0
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
        sleepFor: { _ in },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { factory },
        onStateChanged: { enqueuedSchedule = enqueuedSchedule || $0.latestSchedule.isEmpty == false }
    )
    let firstSession = FakePracticeSession(sequencerPlaybackService: playbackService, settingsProvider: FakeSettingsProvider())
    let replacementSession = FakePracticeSession(sequencerPlaybackService: playbackService, settingsProvider: FakeSettingsProvider())
    service.updatePracticeSession(firstSession)
    service.setEnabled(true)
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [60], started: [60], ended: []),
        nowUptimeSeconds: 0
    )
    nowUptime = 0.2
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
        sleepFor: { _ in },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { factory },
        onStateChanged: { enqueuedSchedule = enqueuedSchedule || $0.latestSchedule.isEmpty == false }
    )
    let session = FakePracticeSession(sequencerPlaybackService: playbackService, settingsProvider: FakeSettingsProvider())
    service.updatePracticeSession(session)
    service.setEnabled(true)
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [60], started: [60], ended: []),
        nowUptimeSeconds: 0
    )
    nowUptime = 0.2
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
    let selectedKind: ImprovBackendKind = .localRule
    let backend = ControlledBackend(kind: selectedKind)
    let playbackService = NonAdvancingPlaybackService()
    let factory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )
    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { factory },
        onStateChanged: { _ in }
    )
    let session = FakePracticeSession(sequencerPlaybackService: playbackService, settingsProvider: FakeSettingsProvider())
    service.updatePracticeSession(session)
    service.setEnabled(true)
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [60], started: [60], ended: []),
        nowUptimeSeconds: 0
    )
    nowUptime = 0.2
    #expect(await backend.waitForCall())

    service.setEnabled(false)
    service.setEnabled(true)
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [64], started: [64], ended: []),
        nowUptimeSeconds: nowUptime
    )
    nowUptime = 0.4
    #expect(await backend.waitForCall(minimumCount: 2))

    await backend.resume(with: .schedule([], backendLatencyMS: nil))
    for _ in 0 ..< 200 {
        await Task.yield()
    }
    #expect(await backend.generateCallCount() == 2)

    await backend.resume(with: .schedule([], backendLatencyMS: nil))
    service.setEnabled(false)
}
