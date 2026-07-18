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

    init(kind: ImprovBackendKind, displayName: String = "Controlled") {
        self.kind = kind
        self.displayName = displayName
    }

    func generatePlaybackPlan(request _: ImprovGenerateRequestV2, timeout _: Duration) async throws -> ImprovBackendPlaybackPlan {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitForCall(timeout: Duration = .seconds(2)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if continuation != nil { return true }
            // ponytail: 1 ms polling keeps this test helper deterministic without a bespoke test clock.
            try? await Task.sleep(for: .milliseconds(1))
        }
        return continuation != nil
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
func continuousDuetRequestsGenerationBeforeUserReleasesKey() async {
    var nowUptime: TimeInterval = 0

    let selectedKind: ImprovBackendKind = .localRule
    let backend = ControlledBackend(kind: selectedKind)

    let aiPlaybackService = NonAdvancingPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { aiPlaybackService },
        makeExternalMIDIPlaybackService: { _ in aiPlaybackService }
    )

    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
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
        keyContact: KeyContactResult(down: [60], started: [60], ended: []),
        nowUptimeSeconds: nowUptime
    )
    nowUptime = 0.2

    #expect(await backend.waitForCall())

    let schedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 67, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 67)),
    ]
    await backend.resume(with: .schedule(schedule, backendLatencyMS: nil))

    service.setEnabled(false)
}

@Test
@MainActor
func continuousDuetRequestsGenerationForMIDI2Input() async {
    var nowUptime: TimeInterval = 0

    let selectedKind: ImprovBackendKind = .localRule
    let backend = ControlledBackend(kind: selectedKind)

    let aiPlaybackService = NonAdvancingPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { aiPlaybackService },
        makeExternalMIDIPlaybackService: { _ in aiPlaybackService }
    )

    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
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

    #expect(await backend.waitForCall())

    await backend.resume(with: .schedule([
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 67, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 67)),
    ], backendLatencyMS: nil))

    service.setEnabled(false)
}
