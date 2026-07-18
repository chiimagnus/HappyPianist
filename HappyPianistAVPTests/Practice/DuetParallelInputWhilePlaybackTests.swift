import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
private final class FakeBackendDiscoveryService: BonjourBackendDiscoveryServiceProtocol {
    var state: BonjourBackendDiscoveryService.State = .idle
    func start() {}
    func stop() {}
}

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

private actor CountingScheduleBackend: ImprovBackendProtocol {
    nonisolated let kind: ImprovBackendKind
    nonisolated let displayName: String

    private let playbackPlan: ImprovBackendPlaybackPlan
    private var generateCallCountValue = 0

    init(kind: ImprovBackendKind, displayName: String = "Fake", playbackPlan: ImprovBackendPlaybackPlan) {
        self.kind = kind
        self.displayName = displayName
        self.playbackPlan = playbackPlan
    }

    func generatePlaybackPlan(request _: ImprovGenerateRequestV2, timeout _: Duration) async throws -> ImprovBackendPlaybackPlan {
        generateCallCountValue += 1
        return playbackPlan
    }

    func generateCallCount() -> Int {
        generateCallCountValue
    }
}

@MainActor
private final class NonAdvancingPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var playCallCount = 0

    func warmUp() throws {}
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}

    func play(fromSeconds _: TimeInterval) throws {
        playCallCount += 1
    }

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
func aiPlaybackDoesNotBlockSecondContinuousWindowRequest() async {
    var nowUptime: TimeInterval = 0

    let orchestrator = FakeDiscoveryOrchestrator()
    let selectedKind: ImprovBackendKind = .localRule
    let schedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 10.0, kind: .noteOff(midi: 60)),
    ]

    let backend = CountingScheduleBackend(kind: selectedKind, playbackPlan: .schedule(schedule, backendLatencyMS: nil))

    let aiPlaybackService = NonAdvancingPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { aiPlaybackService },
        makeExternalMIDIPlaybackService: { _ in aiPlaybackService }
    )

    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
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
        keyContact: KeyContactResult(down: [60], started: [60], ended: []),
        nowUptimeSeconds: 0.0
    )
    nowUptime = 0.3

    for _ in 0 ..< 500 {
        await Task.yield()
        if await backend.generateCallCount() >= 3 { break }
    }
    #expect(await backend.generateCallCount() == 3)

    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [64], started: [64], ended: []),
        nowUptimeSeconds: 0.3
    )
    nowUptime = 0.7

    for _ in 0 ..< 500 {
        await Task.yield()
        if await backend.generateCallCount() >= 6 { break }
    }
    #expect(await backend.generateCallCount() == 6)

    service.setEnabled(false)
}
