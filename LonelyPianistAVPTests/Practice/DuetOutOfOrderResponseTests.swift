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

    private var continuations: [CheckedContinuation<ImprovBackendPlaybackPlan, Error>] = []

    init(kind: ImprovBackendKind, displayName: String = "Controlled") {
        self.kind = kind
        self.displayName = displayName
    }

    func generatePlaybackPlan(request _: ImprovGenerateRequest, timeout _: Duration) async throws -> ImprovBackendPlaybackPlan {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForCallCount(_ expected: Int) async {
        _ = await waitForCallCount(expected, maxYields: 10_000)
    }

    func waitForCallCount(_ expected: Int, maxYields: Int) async -> Bool {
        for _ in 0 ..< maxYields {
            if continuations.count >= expected { return true }
            await Task.yield()
        }
        return continuations.count >= expected
    }

    func resumeCall(at index: Int, with plan: ImprovBackendPlaybackPlan) {
        guard index < continuations.count else { return }
        let continuation = continuations.remove(at: index)
        continuation.resume(returning: plan)
    }

    func resumeAllRemaining(with plan: ImprovBackendPlaybackPlan) {
        for continuation in continuations {
            continuation.resume(returning: plan)
        }
        continuations.removeAll(keepingCapacity: true)
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
func outOfOrderResponsesAreEnqueuedInSendOrder() async throws {
    var nowUptime: TimeInterval = 0

    let selectedKind: ImprovBackendKind = .localRule
    let backend = ControlledBackend(kind: selectedKind)

    let aiPlaybackService = NonAdvancingPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { aiPlaybackService },
        makeExternalMIDIPlaybackService: { _ in aiPlaybackService }
    )

    var enqueuedFirstNoteMIDIs: [Int] = []
    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: FakeDiscoveryOrchestrator(),
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { state in
            guard let first = state.latestSchedule.first else { return }
            guard case let .noteOn(midi, _) = first.kind else { return }
            if enqueuedFirstNoteMIDIs.last != midi {
                enqueuedFirstNoteMIDIs.append(midi)
            }
        }
    )

    let practicePlaybackService = NonAdvancingPlaybackService()
    let session = FakePracticeSession(
        sequencerPlaybackService: practicePlaybackService,
        settingsProvider: FakeSettingsProvider()
    )
    service.updatePracticeSession(session)
    service.setEnabled(true)

    // Ensure any unfinished backend continuations are resumed to avoid test-runner crashes.
    defer {
        Task {
            let fallbackSchedule = [
                PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
                PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 60)),
            ]
            await backend.resumeAllRemaining(with: .schedule(fallbackSchedule, backendLatencyMS: nil))
        }
    }

    // Send 2 phrases (force immediate send via long-phrase threshold).
    nowUptime = 0.0
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [], started: [60], ended: []),
        nowUptimeSeconds: nowUptime
    )
    nowUptime = 3.1
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [], started: [], ended: [60]),
        nowUptimeSeconds: nowUptime
    )

    for _ in 0 ..< 50 { await Task.yield() }
    #expect(await backend.waitForCallCount(1, maxYields: 10_000))

    nowUptime = 4.0
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [], started: [64], ended: []),
        nowUptimeSeconds: nowUptime
    )
    nowUptime = 7.2
    service.recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: false,
        keyContact: KeyContactResult(down: [], started: [], ended: [64]),
        nowUptimeSeconds: nowUptime
    )

    try #require(await backend.waitForCallCount(2, maxYields: 10_000))

    // Resume out of order: second call returns before the first.
    let schedule1 = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 60)),
    ]
    let schedule2 = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 64, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 64)),
    ]

    await backend.resumeCall(at: 1, with: .schedule(schedule2, backendLatencyMS: nil))
    await backend.resumeCall(at: 0, with: .schedule(schedule1, backendLatencyMS: nil))

    for _ in 0 ..< 10_000 {
        await Task.yield()
        if enqueuedFirstNoteMIDIs.count >= 2 { break }
    }

    try #require(enqueuedFirstNoteMIDIs.count >= 2)
    #expect(enqueuedFirstNoteMIDIs[0] == 60)
    #expect(enqueuedFirstNoteMIDIs[1] == 64)

    service.setEnabled(false)
}
