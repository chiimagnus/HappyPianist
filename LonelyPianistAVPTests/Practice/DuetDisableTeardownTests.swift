import Foundation
import ImprovProtocol
@testable import LonelyPianistAVP
import os
import Testing

@MainActor
private final class FakeDiscoveryOrchestrator: ImprovBackendDiscoveryOrchestrating {
    func start(for _: ImprovBackendKind) {}
    func stopAll() {}
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

    func aiPerformanceTickRange(maxMeasures _: Int) -> (startTick: Int, endTick: Int)? { nil }
    func stopVirtualPianoInput() {}
    func stopAudioRecognition() {}
    func prepareAudioRecognitionSuppressWindowForPlayback() -> Date { .now }
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

    func waitForCall(maxYields: Int = 10_000) async -> Bool {
        for _ in 0 ..< maxYields {
            if continuation != nil { return true }
            await Task.yield()
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
    private var nowSeconds: TimeInterval = 0

    func warmUp() throws {}
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        nowSeconds += 1
        return nowSeconds
    }
    func playOneShot(noteOns _: [PracticeOneShotNoteOn], durationSeconds _: TimeInterval) throws {}
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}

@MainActor
private struct FakeSettingsProvider: PracticeSessionSettingsProviderProtocol {
    var manualAdvanceMode: ManualAdvanceMode { .step }
    var practiceHandMode: PracticeHandMode { .both }
    var audioRecognitionDetectorMode: PracticeAudioRecognitionDetectorMode { .harmonicTemplate }
    var soundRoutingSettings: PracticeSoundRoutingSettings {
        PracticeSoundRoutingSettings(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false)
    }
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
        logger: Logger(subsystem: "test", category: "ai-perf"),
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

    // Trigger one send (long phrase for immediate send).
    nowUptime = 0.0
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [], started: [60], ended: []),
        nowUptimeSeconds: nowUptime
    )
    nowUptime = 3.2
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [], started: [], ended: [60]),
        nowUptimeSeconds: nowUptime
    )

    #expect(await backend.waitForCall())

    // Disable before the backend replies.
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
