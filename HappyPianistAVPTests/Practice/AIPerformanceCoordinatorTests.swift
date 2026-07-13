import Foundation
@testable import HappyPianistAVP
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
        request _: ImprovGenerateRequestV2,
        timeout _: Duration
    ) async throws -> ImprovBackendPlaybackPlan {
        playbackPlan
    }
}

private actor RecordingSeedBackend: ImprovBackendProtocol {
	nonisolated let kind: ImprovBackendKind
	nonisolated let displayName: String

	private let playbackPlan: ImprovBackendPlaybackPlan
	private(set) var requestedSeeds: [UInt64] = []

	init(kind: ImprovBackendKind, displayName: String = "Recording", playbackPlan: ImprovBackendPlaybackPlan) {
		self.kind = kind
		self.displayName = displayName
		self.playbackPlan = playbackPlan
	}

	func generatePlaybackPlan(
		request: ImprovGenerateRequestV2,
		timeout _: Duration
	) async throws -> ImprovBackendPlaybackPlan {
		if let seed = request.params.seed {
			requestedSeeds.append(seed)
		}
		return playbackPlan
	}
}

private actor SequencedCandidateBackend: ImprovBackendProtocol {
	nonisolated let kind: ImprovBackendKind
	nonisolated let displayName: String

	private let schedules: [[PracticeSequencerMIDIEvent]]
	private let failingIndices: Set<Int>
	private(set) var callCount = 0

	init(
		kind: ImprovBackendKind,
		displayName: String = "Sequenced",
		schedules: [[PracticeSequencerMIDIEvent]],
		failingIndices: Set<Int> = []
	) {
		self.kind = kind
		self.displayName = displayName
		self.schedules = schedules
		self.failingIndices = failingIndices
	}

	func generatePlaybackPlan(
		request _: ImprovGenerateRequestV2,
		timeout _: Duration
	) async throws -> ImprovBackendPlaybackPlan {
		let requestIndex = callCount
		let index = min(requestIndex, max(0, schedules.count - 1))
		callCount += 1
		if failingIndices.contains(requestIndex) {
			throw CancellationError()
		}
		return .schedule(schedules[index], backendLatencyMS: nil)
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
    let settingsProvider: any PracticeSessionSettingsProviderProtocol

    private(set) var stopVirtualPianoInputCallCount = 0
    private(set) var stopAudioRecognitionCallCount = 0
    private(set) var prepareSuppressWindowCallCount = 0
    private(set) var refreshAudioRecognitionCallCount = 0

    init(
        currentStep: PracticeStep?,
        sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol,
        settingsProvider: any PracticeSessionSettingsProviderProtocol = FakeSettingsProvider()
    ) {
        self.currentStep = currentStep
        self.sequencerPlaybackService = sequencerPlaybackService
        self.settingsProvider = settingsProvider
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

private struct FakeSettingsProvider: PracticeSessionSettingsProviderProtocol {
    var manualAdvanceMode: ManualAdvanceMode { .step }
    var practiceHandMode: PracticeHandMode { .both }
    var soundRoutingSettings: PracticeSoundRoutingSettings { PracticeSoundRoutingSettings(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false) }
}

@Test
@MainActor
func enableDisableAreIdempotent() async {
    let nowUptime: TimeInterval = 0
    var states: [AIPerformanceService.State] = []

    let backendService = FakeBackendDiscoveryService()
    let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
    let selectedKind: ImprovBackendKind = .networkBonjourHTTPAriaV2
    let aiPlaybackService = FakeSequencerPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { aiPlaybackService },
        makeExternalMIDIPlaybackService: { _ in aiPlaybackService }
    )
    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: []),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { states.append($0) }
    )

    let practicePlaybackService = FakeSequencerPlaybackService()
    let session = FakePracticeSession(
        currentStep: PracticeStep(tick: 0, notes: []),
        sequencerPlaybackService: practicePlaybackService
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
    let aiPlaybackService = FakeSequencerPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { aiPlaybackService },
        makeExternalMIDIPlaybackService: { _ in aiPlaybackService }
    )
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
        aiPlaybackServiceFactory: { aiPlaybackFactory },
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
        if aiPlaybackService.playCallCount > 0 {
            break
        }
    }

    #expect(aiPlaybackService.playCallCount > 0)
    let didBecomeActive = states.contains { $0.isAIPerformanceActive }
    #expect(didBecomeActive)

    service.setEnabled(false)

    for _ in 0 ..< 500 {
        await Task.yield()
        if aiPlaybackService.stopCallCount > 0 {
            break
        }
    }

    #expect(aiPlaybackService.stopCallCount > 0)
    #expect(states.last?.isAIPerformanceActive == false)
}

@Test
@MainActor
func shutdownPreventsFurtherEnable() async {
    let nowUptime: TimeInterval = 0

    let backendService = FakeBackendDiscoveryService()
    let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
    let selectedKind: ImprovBackendKind = .networkBonjourHTTPAriaV2
    let aiPlaybackService = FakeSequencerPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { aiPlaybackService },
        makeExternalMIDIPlaybackService: { _ in aiPlaybackService }
    )
    let service = AIPerformanceService(
        logger: Logger(subsystem: "test", category: "ai-perf"),
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: []),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { _ in }
    )

    let playbackService = FakeSequencerPlaybackService()
    service.updatePracticeSession(
        FakePracticeSession(
            currentStep: PracticeStep(tick: 0, notes: []),
            sequencerPlaybackService: playbackService
        )
    )

    service.setEnabled(true)

    for _ in 0 ..< 50 {
        await Task.yield()
    }

    #expect(orchestrator.startCallCount == 1)

    service.shutdown()
    for _ in 0 ..< 50 {
        await Task.yield()
    }
    #expect(orchestrator.stopAllCallCount == 1)

    service.setEnabled(true)
    #expect(orchestrator.startCallCount == 1)
}

@Test
@MainActor
func localRuleBackendUsesDeterministicMultiCandidateSeeds() async {
	let nowUptime: TimeInterval = 0

	let backendService = FakeBackendDiscoveryService()
	let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
	let selectedKind: ImprovBackendKind = .localRule
	let schedule = [
		PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 72, velocity: 90)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 72)),
	]
	let backend = RecordingSeedBackend(kind: selectedKind, playbackPlan: .schedule(schedule, backendLatencyMS: nil))

	let playbackService = FakeSequencerPlaybackService()
	let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
		makeLocalSamplerPlaybackService: { playbackService },
		makeExternalMIDIPlaybackService: { _ in playbackService }
	)
	let service = AIPerformanceService(
		logger: Logger(subsystem: "test", category: "ai-perf"),
		nowUptimeSeconds: { nowUptime },
		sleepFor: { _ in },
		discoveryOrchestrator: orchestrator,
		backendRegistry: ImprovBackendRegistry(backends: [backend]),
		selectedBackendKind: { selectedKind },
		aiPlaybackServiceFactory: { aiPlaybackFactory },
		onStateChanged: { _ in }
	)
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
		let seeds = await backend.requestedSeeds
		if seeds.count == 3 { break }
	}

	let seeds = await backend.requestedSeeds
	let expectedBaseSeed = UInt64(1) << 32
	#expect(seeds == [
		expectedBaseSeed,
		expectedBaseSeed &+ 0x9E3779B97F4A7C15,
		expectedBaseSeed &+ (2 &* 0x9E3779B97F4A7C15),
	])
}

@Test
@MainActor
func networkBackendRemainsSingleCandidate() async {
	let nowUptime: TimeInterval = 0

	let backendService = FakeBackendDiscoveryService()
	let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
	let selectedKind: ImprovBackendKind = .networkBonjourHTTPAriaV2
	let schedule = [
		PracticeSequencerMIDIEvent(timeSeconds: 0.0, kind: .noteOn(midi: 72, velocity: 90)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 72)),
	]
	let backend = RecordingSeedBackend(kind: selectedKind, playbackPlan: .schedule(schedule, backendLatencyMS: nil))

	let playbackService = FakeSequencerPlaybackService()
	let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
		makeLocalSamplerPlaybackService: { playbackService },
		makeExternalMIDIPlaybackService: { _ in playbackService }
	)
	let service = AIPerformanceService(
		logger: Logger(subsystem: "test", category: "ai-perf"),
		nowUptimeSeconds: { nowUptime },
		sleepFor: { _ in },
		discoveryOrchestrator: orchestrator,
		backendRegistry: ImprovBackendRegistry(backends: [backend]),
		selectedBackendKind: { selectedKind },
		aiPlaybackServiceFactory: { aiPlaybackFactory },
		onStateChanged: { _ in }
	)
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
		let seeds = await backend.requestedSeeds
		if seeds.isEmpty == false { break }
	}

	let seeds = await backend.requestedSeeds
	#expect(seeds.count == 1)
	#expect(seeds.first == (UInt64(1) << 32))
}

@Test
@MainActor
func localRuleCandidateSelectionPrefersHigherQualityWindow() async {
	let nowUptime: TimeInterval = 0
	var states: [AIPerformanceService.State] = []

	let backendService = FakeBackendDiscoveryService()
	let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
	let selectedKind: ImprovBackendKind = .localRule
	let backend = SequencedCandidateBackend(
		kind: selectedKind,
		schedules: [
			[
				PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 60, velocity: 100)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.03, kind: .noteOn(midi: 61, velocity: 100)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.06, kind: .noteOn(midi: 62, velocity: 100)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.09, kind: .noteOn(midi: 63, velocity: 100)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.12, kind: .noteOn(midi: 64, velocity: 100)),
			],
                [
                    PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 72, velocity: 90)),
                    PracticeSequencerMIDIEvent(timeSeconds: 0.25, kind: .noteOff(midi: 72)),
                    PracticeSequencerMIDIEvent(timeSeconds: 0.30, kind: .noteOn(midi: 76, velocity: 88)),
                    PracticeSequencerMIDIEvent(timeSeconds: 0.55, kind: .noteOff(midi: 76)),
			],
			[
				PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 79, velocity: 90)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.08, kind: .noteOff(midi: 79)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.10, kind: .noteOn(midi: 79, velocity: 90)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.18, kind: .noteOff(midi: 79)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.20, kind: .noteOn(midi: 79, velocity: 90)),
			],
		],
		failingIndices: [0]
	)

	let playbackService = FakeSequencerPlaybackService()
	let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
		makeLocalSamplerPlaybackService: { playbackService },
		makeExternalMIDIPlaybackService: { _ in playbackService }
	)
	let service = AIPerformanceService(
		logger: Logger(subsystem: "test", category: "ai-perf"),
		nowUptimeSeconds: { nowUptime },
		sleepFor: { _ in },
		discoveryOrchestrator: orchestrator,
		backendRegistry: ImprovBackendRegistry(backends: [backend]),
		selectedBackendKind: { selectedKind },
		aiPlaybackServiceFactory: { aiPlaybackFactory },
		onStateChanged: { states.append($0) }
	)
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
		if playbackService.playCallCount > 0,
		   states.last?.lastImprovStatusText?.contains("candidates=2") == true {
			break
		}
	}

	let latestSchedule = states.last?.latestSchedule ?? []
	let firstNoteOn = latestSchedule.first { if case .noteOn = $0.kind { return true } else { return false } }
	#expect(playbackService.playCallCount > 0)
	#expect(firstNoteOn != nil)
	if let firstNoteOn, case let .noteOn(midi, _) = firstNoteOn.kind {
		#expect(midi == 72)
	}
	#expect(states.last?.lastImprovStatusText?.contains("q=acceptable") == true)
	#expect(states.last?.lastImprovStatusText?.contains("candidates=2") == true)
}

@Test
@MainActor
func allRejectedCandidatesPreferSilenceWithRejectStatus() async {
	let nowUptime: TimeInterval = 0
	var states: [AIPerformanceService.State] = []

	let backendService = FakeBackendDiscoveryService()
	let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
	let selectedKind: ImprovBackendKind = .localRule
	let backend = SequencedCandidateBackend(
		kind: selectedKind,
		schedules: [
			[
				PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 61, velocity: 100)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.03, kind: .noteOn(midi: 62, velocity: 100)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.06, kind: .noteOn(midi: 63, velocity: 100)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.09, kind: .noteOn(midi: 64, velocity: 100)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.12, kind: .noteOn(midi: 65, velocity: 100)),
			],
			[
				PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 60, velocity: 100)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.03, kind: .noteOff(midi: 60)),
			],
			[
				PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 62, velocity: 100)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.03, kind: .noteOn(midi: 63, velocity: 100)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.06, kind: .noteOn(midi: 64, velocity: 100)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.09, kind: .noteOn(midi: 65, velocity: 100)),
				PracticeSequencerMIDIEvent(timeSeconds: 0.12, kind: .noteOn(midi: 66, velocity: 100)),
			],
			]
	)

	let playbackService = FakeSequencerPlaybackService()
	let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
		makeLocalSamplerPlaybackService: { playbackService },
		makeExternalMIDIPlaybackService: { _ in playbackService }
	)
	let service = AIPerformanceService(
		logger: Logger(subsystem: "test", category: "ai-perf"),
		nowUptimeSeconds: { nowUptime },
		sleepFor: { _ in },
		discoveryOrchestrator: orchestrator,
		backendRegistry: ImprovBackendRegistry(backends: [backend]),
		selectedBackendKind: { selectedKind },
		aiPlaybackServiceFactory: { aiPlaybackFactory },
		onStateChanged: { states.append($0) }
	)
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
		if states.last?.lastImprovStatusText?.contains("q=reject") == true { break }
	}

	#expect(playbackService.playCallCount == 0)
	#expect(states.last?.lastImprovStatusText?.contains("q=reject") == true)
	#expect(states.last?.lastImprovStatusText?.contains("candidates=3") == true)
	#expect(states.last?.lastImprovStatusText?.contains("topReject=densityOverload") == true)
}
