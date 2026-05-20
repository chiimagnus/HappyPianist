import Foundation
@testable import LonelyPianistAVP
import Testing
import os

@MainActor
private final class FakeBackendDiscoveryService: AIPerformanceBackendDiscoveryServiceProtocol {
    var resolvedEndpoint: (host: String, port: Int)?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    init(resolvedEndpoint: (host: String, port: Int)? = nil) {
        self.resolvedEndpoint = resolvedEndpoint
    }

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }
}

private struct FakeBackendClient: ImprovBackendClientProtocol {
    var result: Result<ImprovResultResponse, Error>

    func generate(
        host _: String,
        port _: Int,
        request _: ImprovGenerateRequest,
        timeoutSeconds _: TimeInterval
    ) async throws -> ImprovResultResponse {
        try result.get()
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
    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        backendDiscoveryService: backend,
        backendClient: FakeBackendClient(result: .success(.init(type: "result", protocolVersion: 1, notes: [], latencyMS: nil))),
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
    service.setEnabled(true)
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

    let backend = FakeBackendDiscoveryService(resolvedEndpoint: (host: "127.0.0.1", port: 1234))
    let response = ImprovResultResponse(
        type: "result",
        protocolVersion: 1,
        notes: [
            ImprovDialogueNote(note: 60, velocity: 90, time: 0.0, duration: 10.0),
        ],
        latencyMS: nil
    )

    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        backendDiscoveryService: backend,
        backendClient: FakeBackendClient(result: .success(response)),
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
    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        backendDiscoveryService: backend,
        backendClient: FakeBackendClient(result: .success(.init(type: "result", protocolVersion: 1, notes: [], latencyMS: nil))),
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

