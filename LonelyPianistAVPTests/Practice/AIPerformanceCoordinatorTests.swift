import Foundation
@testable import LonelyPianistAVP
import ImprovProtocol
import Testing
import os

@MainActor
private final class FakeBackendDiscoveryService: BonjourBackendDiscoveryServiceProtocol {
    var state: BonjourBackendDiscoveryService.State = .idle
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start() {
        startCallCount += 1
        if case .idle = state {
            state = .discovering
        }
    }

    func stop() {
        stopCallCount += 1
        if case .discovering = state {
            state = .idle
        }
    }
}

private actor FakeScheduleBackend: ImprovBackendProtocol {
    nonisolated let kind: ImprovBackendKind
    nonisolated let displayName: String

    private let playbackPlan: ImprovBackendPlaybackPlan

    init(kind: ImprovBackendKind, displayName: String = "Fake", playbackPlan: ImprovBackendPlaybackPlan) {
        self.kind = kind
        self.displayName = displayName
        self.playbackPlan = playbackPlan
    }

    func generatePlaybackPlan(
        request _: ImprovGenerateRequest,
        timeout _: Duration
    ) async throws -> ImprovBackendPlaybackPlan {
        playbackPlan
    }
}

@MainActor
private final class FakeSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var warmUpCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var loadCallCount = 0
    private(set) var playCallCount = 0

    var currentSecondsValue: TimeInterval = 0

    func warmUp() throws {
        warmUpCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func load(sequence _: PracticeSequencerSequence) throws {
        loadCallCount += 1
    }

    func play(fromSeconds _: TimeInterval) throws {
        playCallCount += 1
    }

    func currentSeconds() -> TimeInterval {
        currentSecondsValue
    }

    func playOneShot(midiNotes _: [Int], durationSeconds _: TimeInterval) throws {}
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}

@MainActor
private final class FakePracticeSession: AIPerformancePracticeSessionProtocol {
    var autoplayState: PracticeSessionAutoplayState = .off
    var isManualReplayPlaying: Bool = false
    var currentStep: PracticeStep?
    var autoplayTimeline: AutoplayPerformanceTimeline = .empty
    var tempoMap: MusicXMLTempoMap = MusicXMLTempoMap(tempoEvents: [])
    var pedalTimeline: MusicXMLPedalTimeline?
    let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol

    private(set) var stopVirtualPianoInputCallCount = 0
    private(set) var stopAudioRecognitionCallCount = 0
    private(set) var prepareSuppressWindowCallCount = 0
    private(set) var refreshAudioRecognitionCallCount = 0

    init(
        currentStep: PracticeStep?,
        sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol
    ) {
        self.currentStep = currentStep
        self.sequencerPlaybackService = sequencerPlaybackService
    }

    func aiPerformanceTickRange(maxMeasures _: Int) -> (startTick: Int, endTick: Int)? {
        nil
    }

    func stopVirtualPianoInput() {
        stopVirtualPianoInputCallCount += 1
    }

    func stopAudioRecognition() {
        stopAudioRecognitionCallCount += 1
    }

    func prepareAudioRecognitionSuppressWindowForPlayback() -> Date {
        prepareSuppressWindowCallCount += 1
        return .now
    }

    func refreshAudioRecognitionForCurrentState() {
        refreshAudioRecognitionCallCount += 1
    }
}

@Test
@MainActor
func enableDisableAreIdempotent() async {
    var nowUptime: TimeInterval = 0
    var states: [AIPerformanceService.State] = []

    let backend = FakeBackendDiscoveryService()
    let selectedKind: ImprovBackendKind = .networkBonjourHTTP
    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        backendDiscoveryService: backend,
        backendRegistry: ImprovBackendRegistry(backends: []),
        selectedBackendKind: { selectedKind },
        pollInterval: .milliseconds(1),
        silenceTimeoutSeconds: 999,
        onStateChanged: { states.append($0) }
    )

    let playbackService = FakeSequencerPlaybackService()
    let session = FakePracticeSession(
        currentStep: PracticeStep(tick: 0, notes: []),
        sequencerPlaybackService: playbackService
    )
    service.updatePracticeSession(session)

    service.setEnabled(true)
    service.setEnabled(true)

    for _ in 0 ..< 50 {
        await Task.yield()
    }
    #expect(backend.startCallCount == 1)

    service.setEnabled(false)
    service.setEnabled(false)
    #expect(backend.stopCallCount == 1)

    #expect(states.last?.isAIPerformanceActive == false)
}

@Test
@MainActor
func disableCancelsPendingPlaybackAndStopsSequencer() async {
    var nowUptime: TimeInterval = 0
    var states: [AIPerformanceService.State] = []

    let backend = FakeBackendDiscoveryService()
    let selectedKind: ImprovBackendKind = .localDeterministic
    let schedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 10.0, kind: .noteOff(midi: 60)),
    ]
    let fakeBackend = FakeScheduleBackend(kind: selectedKind, playbackPlan: .schedule(schedule))

    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        backendDiscoveryService: backend,
        backendRegistry: ImprovBackendRegistry(backends: [fakeBackend]),
        selectedBackendKind: { selectedKind },
        pollInterval: .milliseconds(1),
        silenceTimeoutSeconds: 0.01,
        onStateChanged: { states.append($0) }
    )

    let playbackService = FakeSequencerPlaybackService()
    let session = FakePracticeSession(
        currentStep: PracticeStep(tick: 0, notes: []),
        sequencerPlaybackService: playbackService
    )
    service.updatePracticeSession(session)

    service.setEnabled(true)

    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 90),
            channel: 1,
            group: 0,
            source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: Date(timeIntervalSince1970: 0),
            receivedAtUptimeSeconds: 0
        )
    )

    nowUptime = 1

    for _ in 0 ..< 500 {
        await Task.yield()
        if playbackService.playCallCount > 0 {
            break
        }
    }

    #expect(playbackService.playCallCount > 0)
    #expect(states.contains(where: { $0.isAIPerformanceActive }))

    service.setEnabled(false)

    for _ in 0 ..< 500 {
        await Task.yield()
        if playbackService.stopCallCount > 0 {
            break
        }
    }

    #expect(playbackService.stopCallCount > 0)
    #expect(states.last?.isAIPerformanceActive == false)
}

@Test
@MainActor
func shutdownPreventsFurtherEnable() async {
    var nowUptime: TimeInterval = 0

    let backend = FakeBackendDiscoveryService()
    let selectedKind: ImprovBackendKind = .networkBonjourHTTP
    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        backendDiscoveryService: backend,
        backendRegistry: ImprovBackendRegistry(backends: []),
        selectedBackendKind: { selectedKind },
        pollInterval: .milliseconds(1),
        silenceTimeoutSeconds: 0.01,
        onStateChanged: { _ in }
    )

    let playbackService = FakeSequencerPlaybackService()
    service.updatePracticeSession(
        FakePracticeSession(
            currentStep: PracticeStep(tick: 0, notes: []),
            sequencerPlaybackService: playbackService
        )
    )

    service.shutdown()
    service.setEnabled(true)

    for _ in 0 ..< 50 {
        await Task.yield()
    }

    #expect(backend.startCallCount == 0)
}
