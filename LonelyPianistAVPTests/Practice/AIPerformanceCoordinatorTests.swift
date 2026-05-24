import Foundation
import ImprovProtocol
@testable import LonelyPianistAVP
import os
import Testing

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

@MainActor
private final class FakeDiscoveryOrchestrator: ImprovBackendDiscoveryOrchestrating {
    private let service: FakeBackendDiscoveryService
    private(set) var startCallCount = 0
    private(set) var stopAllCallCount = 0

    init(service: FakeBackendDiscoveryService) {
        self.service = service
    }

    func start(for _: ImprovBackendKind) {
        startCallCount += 1
        service.start()
    }

    func stopAll() {
        stopAllCallCount += 1
        service.stop()
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

    func playOneShot(noteOns _: [PracticeOneShotNoteOn], durationSeconds _: TimeInterval) throws {}
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
    var tempoMap: MusicXMLTempoMap = .init(tempoEvents: [])
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

private actor TestSleeper {
    private var pending: [CheckedContinuation<Void, Never>] = []
    private(set) var requestedDurations: [Duration] = []

    func sleep(for duration: Duration) async {
        requestedDurations.append(duration)
        await withCheckedContinuation { continuation in
            pending.append(continuation)
        }
    }

    func resumeAll() {
        let current = pending
        pending.removeAll(keepingCapacity: true)
        for continuation in current {
            continuation.resume()
        }
    }
}

@Test
@MainActor
func enableDisableAreIdempotent() async {
    var nowUptime: TimeInterval = 0
    var states: [AIPerformanceService.State] = []

    let backendService = FakeBackendDiscoveryService()
    let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
    let selectedKind: ImprovBackendKind = .networkBonjourHTTPDuet
    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: []),
        selectedBackendKind: { selectedKind },
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
    #expect(orchestrator.startCallCount == 1)

    service.setEnabled(false)
    service.setEnabled(false)
    #expect(orchestrator.stopAllCallCount == 1)

    #expect(states.last?.isAIPerformanceActive == false)
}

@Test
@MainActor
func disableCancelsPendingPlaybackAndStopsSequencer() async {
    var nowUptime: TimeInterval = 0
    var states: [AIPerformanceService.State] = []

    let backendService = FakeBackendDiscoveryService()
    let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
    let selectedKind: ImprovBackendKind = .localRule
    let schedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 10.0, kind: .noteOff(midi: 60)),
    ]
    let fakeBackend = FakeScheduleBackend(kind: selectedKind, playbackPlan: .schedule(schedule, backendLatencyMS: nil))

    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: [fakeBackend]),
        selectedBackendKind: { selectedKind },
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
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOff(note: 60, velocity: 0),
            channel: 1,
            group: 0,
            source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: Date(timeIntervalSince1970: 0),
            receivedAtUptimeSeconds: 0.1
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
    let didBecomeActive = states.contains { $0.isAIPerformanceActive }
    #expect(didBecomeActive)

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

    let backendService = FakeBackendDiscoveryService()
    let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
    let selectedKind: ImprovBackendKind = .networkBonjourHTTPDuet
    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: []),
        selectedBackendKind: { selectedKind },
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

    #expect(orchestrator.startCallCount == 0)
}

@Test
@MainActor
func shortPhraseTriggersAfterScheduledDelay() async {
    var nowUptime: TimeInterval = 0

    let sleeper = TestSleeper()
    let backendService = FakeBackendDiscoveryService()
    let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
    let selectedKind: ImprovBackendKind = .localRule
    let schedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 60)),
    ]
    let fakeBackend = FakeScheduleBackend(kind: selectedKind, playbackPlan: .schedule(schedule, backendLatencyMS: nil))
    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        sleepFor: { duration in await sleeper.sleep(for: duration) },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: [fakeBackend]),
        selectedBackendKind: { selectedKind },
        onStateChanged: { _ in }
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
            receivedAtUptimeSeconds: 0.0
        )
    )
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOff(note: 60, velocity: 0),
            channel: 1,
            group: 0,
            source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: Date(timeIntervalSince1970: 0),
            receivedAtUptimeSeconds: 0.1
        )
    )

    for _ in 0 ..< 50 { await Task.yield() }
    #expect(playbackService.playCallCount == 0)

    let durations = await sleeper.requestedDurations
    #expect(durations.isEmpty == false)

    await sleeper.resumeAll()

    for _ in 0 ..< 500 {
        await Task.yield()
        if playbackService.playCallCount > 0 { break }
    }
    #expect(playbackService.playCallCount > 0)
}

@Test
@MainActor
func longPhraseTriggersImmediatelyOnReleaseAll() async {
    var nowUptime: TimeInterval = 0

    let backendService = FakeBackendDiscoveryService()
    let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
    let selectedKind: ImprovBackendKind = .localRule
    let schedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 60)),
    ]
    let fakeBackend = FakeScheduleBackend(kind: selectedKind, playbackPlan: .schedule(schedule, backendLatencyMS: nil))
    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: [fakeBackend]),
        selectedBackendKind: { selectedKind },
        onStateChanged: { _ in }
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
            receivedAtUptimeSeconds: 0.0
        )
    )
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOff(note: 60, velocity: 0),
            channel: 1,
            group: 0,
            source: MIDI1InputEvent.Source(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: Date(timeIntervalSince1970: 0),
            receivedAtUptimeSeconds: 3.2
        )
    )

    for _ in 0 ..< 500 {
        await Task.yield()
        if playbackService.playCallCount > 0 { break }
    }
    #expect(playbackService.playCallCount > 0)
}
