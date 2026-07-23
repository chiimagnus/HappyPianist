import Foundation
@testable import HappyPianistAVP
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

    private let schedule: [PracticeSequencerMIDIEvent]
    private let backendLatencyMS: Int?
    private let responseDelay: Duration?
    private let responseProvider: ImprovBackendKind?
    private let responseGenerationRequestIDOffset: Int?

    init(
        kind: ImprovBackendKind,
        displayName: String = "Fake",
        schedule: [PracticeSequencerMIDIEvent],
        backendLatencyMS: Int? = nil,
        responseDelay: Duration? = nil,
        responseProvider: ImprovBackendKind? = nil,
        responseGenerationRequestIDOffset: Int? = nil
    ) {
        self.kind = kind
        self.displayName = displayName
        self.schedule = schedule
        self.backendLatencyMS = backendLatencyMS
        self.responseDelay = responseDelay
        self.responseProvider = responseProvider
        self.responseGenerationRequestIDOffset = responseGenerationRequestIDOffset
    }

    func generateCreativeResponse(
        phrase _: CreativeDuetPhrase,
        generation: CreativeDuetGeneration,
        timeout _: Duration
    ) async throws -> CreativeDuetResponse {
        if let responseDelay {
            try await Task.sleep(for: responseDelay)
        }
        let responseGeneration: CreativeDuetGeneration
        if let responseGenerationRequestIDOffset {
            responseGeneration = CreativeDuetGeneration(
                requestID: generation.requestID + responseGenerationRequestIDOffset,
                activationID: generation.activationID,
                seed: generation.seed,
                sessionID: generation.sessionID,
                parameters: generation.parameters
            )
        } else {
            responseGeneration = generation
        }
        return CreativeDuetResponse(
            schedule: schedule,
            provider: responseProvider ?? kind,
            generation: responseGeneration,
            provenance: .backendGenerated(latencyMS: backendLatencyMS)
        )
    }
}

private actor RecordingSeedBackend: ImprovBackendProtocol {
    nonisolated let kind: ImprovBackendKind
    nonisolated let displayName: String

    private let schedule: [PracticeSequencerMIDIEvent]
    private let backendLatencyMS: Int?
    private(set) var requestedSeeds: [UInt64] = []

    init(
        kind: ImprovBackendKind,
        displayName: String = "Recording",
        schedule: [PracticeSequencerMIDIEvent],
        backendLatencyMS: Int? = nil
    ) {
        self.kind = kind
        self.displayName = displayName
        self.schedule = schedule
        self.backendLatencyMS = backendLatencyMS
    }

    func generateCreativeResponse(
        phrase _: CreativeDuetPhrase,
        generation: CreativeDuetGeneration,
        timeout _: Duration
    ) async throws -> CreativeDuetResponse {
        requestedSeeds.append(generation.seed)
        return CreativeDuetResponse(
            schedule: schedule,
            provider: kind,
            generation: generation,
            provenance: .backendGenerated(latencyMS: backendLatencyMS)
        )
    }
}

private actor ThrowingBackend: ImprovBackendProtocol {
    enum Failure: Sendable {
        case timeout
        case invalidResponse
    }

    nonisolated let kind: ImprovBackendKind
    nonisolated let displayName: String

    private let failure: Failure
    private(set) var callCount = 0

    init(kind: ImprovBackendKind, failure: Failure, displayName: String = "Throwing") {
        self.kind = kind
        self.failure = failure
        self.displayName = displayName
    }

    func generateCreativeResponse(
        phrase _: CreativeDuetPhrase,
        generation _: CreativeDuetGeneration,
        timeout _: Duration
    ) async throws -> CreativeDuetResponse {
        callCount += 1
        switch failure {
        case .timeout:
            throw URLError(.timedOut)
        case .invalidResponse:
            throw ImprovBackendClientError.invalidResponse
        }
    }
}

private actor SequencedCandidateBackend: ImprovBackendProtocol {
    nonisolated let kind: ImprovBackendKind
    nonisolated let displayName: String

    private let schedules: [[PracticeSequencerMIDIEvent]]
    private(set) var callCount = 0

    init(
        kind: ImprovBackendKind,
        displayName: String = "Sequenced",
        schedules: [[PracticeSequencerMIDIEvent]]
    ) {
        self.kind = kind
        self.displayName = displayName
        self.schedules = schedules
    }

    func generateCreativeResponse(
        phrase _: CreativeDuetPhrase,
        generation: CreativeDuetGeneration,
        timeout _: Duration
    ) async throws -> CreativeDuetResponse {
        let requestIndex = callCount
        let index = min(requestIndex, max(0, schedules.count - 1))
        callCount += 1
        return CreativeDuetResponse(
            schedule: schedules[index],
            provider: kind,
            generation: generation,
            provenance: .backendGenerated(latencyMS: nil)
        )
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

    func stop(resetCommands _: [PerformanceTransportCommand]) {
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

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}

@MainActor
private final class FakePracticeSession: AIPerformancePracticeSessionProtocol {
    let settingsProvider: any PracticeSessionSettingsProviderProtocol = FakeSettingsProvider()

    func refreshAudioRecognitionForCurrentState() {}
}

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

@MainActor
private func recordDuetTestPhrase(_ service: AIPerformanceService) {
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 90),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: Date(timeIntervalSince1970: 0),
            receivedAtUptimeSeconds: 0
        )
    )
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOff(note: 60, velocity: 0),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: Date(timeIntervalSince1970: 0),
            receivedAtUptimeSeconds: 3.2
        )
    )
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
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: []),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { states.append($0) }
    )

    let session = FakePracticeSession()
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
    let fakeBackend = FakeScheduleBackend(kind: selectedKind, schedule: schedule)

    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: [fakeBackend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { states.append($0) }
    )

    let session = FakePracticeSession()
    service.updatePracticeSession(session)

    service.setEnabled(true)

    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 90),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: Date(timeIntervalSince1970: 0),
            receivedAtUptimeSeconds: 0
        )
    )
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOff(note: 60, velocity: 0),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: nil),
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
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: []),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { _ in }
    )

    service.updatePracticeSession(
        FakePracticeSession()
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
func invalidStoredBackendSelectionStopsWithoutFallback() async {
    let suiteName = "AIPerformanceCoordinatorTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Unable to create isolated user defaults.")
        return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("removed_backend", forKey: ImprovBackendSelection.userDefaultsKey)

    let selection = ImprovBackendSelection(userDefaults: defaults)
    #expect(selection.selectedKind() == nil)

    var states: [AIPerformanceService.State] = []
    let diagnosticsReporter = InMemoryDiagnosticsReporter()
    let backendService = FakeBackendDiscoveryService()
    let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
    let playbackService = FakeSequencerPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )
    let service = AIPerformanceService(
        diagnosticsReporter: diagnosticsReporter,
        nowUptimeSeconds: { 0 },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(),
        selectedBackendKind: { selection.selectedKind() },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { states.append($0) }
    )
    defer { service.setEnabled(false) }

    let session = FakePracticeSession()
    service.updatePracticeSession(session)
    service.setEnabled(true)

    for _ in 0 ..< 500 {
        await Task.yield()
        let events = await diagnosticsReporter.events
        if events.contains(where: { $0.reason == "provider=none;failure=invalid_selection" }) { break }
    }

    #expect(orchestrator.startCallCount == 0)
    #expect(states.last?.lastImprovStatusText?.contains("后端选择无效") == true)
    let events = await diagnosticsReporter.events
    #expect(events.contains(where: { $0.reason == "provider=none;failure=invalid_selection" }))
}

@Test
@MainActor
func selectedUnavailableBackendStopsWithoutLocalSubstitution() async {
    let nowUptime: TimeInterval = 0
    var states: [AIPerformanceService.State] = []
    let diagnosticsReporter = InMemoryDiagnosticsReporter()
    let backendService = FakeBackendDiscoveryService()
    let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
    let selectedKind: ImprovBackendKind = .networkBonjourHTTPAriaV2
    let localFallback = RecordingSeedBackend(
        kind: .localRule,
        schedule: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 90)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 72)),
        ]
    )
    let playbackService = FakeSequencerPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )
    let service = AIPerformanceService(
        diagnosticsReporter: diagnosticsReporter,
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: [localFallback]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { states.append($0) }
    )
    defer { service.setEnabled(false) }

    let session = FakePracticeSession()
    service.updatePracticeSession(session)
    service.setEnabled(true)
    recordDuetTestPhrase(service)

    let expectedReason = "provider=network_bonjour_http_aria_v2;failure=unavailable"
    for _ in 0 ..< 500 {
        await Task.yield()
        let events = await diagnosticsReporter.events
        if events.contains(where: { $0.reason == expectedReason }) { break }
    }

    let fallbackSeeds = await localFallback.requestedSeeds
    #expect(fallbackSeeds.isEmpty)
    #expect(playbackService.playCallCount == 0)
    #expect(states.last?.lastImprovStatusText?.contains("后端不可用") == true)
    let events = await diagnosticsReporter.events
    #expect(events.contains(where: { $0.reason == expectedReason }))
}

@Test
@MainActor
func selectedBackendTimeoutAndInvalidResponseStopWithClassifiedDiagnostics() async {
    let scenarios: [(ThrowingBackend.Failure, String, String)] = [
        (.timeout, "timeout", "生成超时"),
        (.invalidResponse, "invalid_response", "响应无效"),
    ]

    for (failure, category, statusText) in scenarios {
        let nowUptime: TimeInterval = 0
        var states: [AIPerformanceService.State] = []
        let diagnosticsReporter = InMemoryDiagnosticsReporter()
        let backendService = FakeBackendDiscoveryService()
        let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
        let selectedKind: ImprovBackendKind = .networkBonjourHTTPAriaV2
        let backend = ThrowingBackend(kind: selectedKind, failure: failure)
        let playbackService = FakeSequencerPlaybackService()
        let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { playbackService },
            makeExternalMIDIPlaybackService: { _ in playbackService }
        )
        let service = AIPerformanceService(
            diagnosticsReporter: diagnosticsReporter,
            nowUptimeSeconds: { nowUptime },
            sleepFor: { _ in },
            discoveryOrchestrator: orchestrator,
            backendRegistry: ImprovBackendRegistry(backends: [backend]),
            selectedBackendKind: { selectedKind },
            aiPlaybackServiceFactory: { aiPlaybackFactory },
            onStateChanged: { states.append($0) }
        )
        defer { service.setEnabled(false) }

        let session = FakePracticeSession()
        service.updatePracticeSession(session)
        service.setEnabled(true)
        recordDuetTestPhrase(service)

        let expectedReason = "provider=network_bonjour_http_aria_v2;failure=\(category)"
        for _ in 0 ..< 500 {
            await Task.yield()
            let events = await diagnosticsReporter.events
            if events.contains(where: { $0.reason == expectedReason }) { break }
        }

        let callCount = await backend.callCount
        #expect(callCount > 0)
        #expect(playbackService.playCallCount == 0)
        #expect(states.last?.lastImprovStatusText?.contains(statusText) == true)
        let events = await diagnosticsReporter.events
        #expect(events.contains(where: { $0.reason == expectedReason }))
    }
}

@Test
@MainActor
func mismatchedCreativeResponseMetadataStopsWithInvalidResponseDiagnostics() async {
    let scenarios: [(provider: ImprovBackendKind?, requestIDOffset: Int?)] = [
        (.localRule, nil),
        (nil, 1),
    ]

    for scenario in scenarios {
        let nowUptime: TimeInterval = 0
        var states: [AIPerformanceService.State] = []
        let diagnosticsReporter = InMemoryDiagnosticsReporter()
        let backendService = FakeBackendDiscoveryService()
        let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
        let selectedKind: ImprovBackendKind = .networkBonjourHTTPAriaV2
        let backend = FakeScheduleBackend(
            kind: selectedKind,
            schedule: [
                PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 90)),
                PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 72)),
            ],
            responseProvider: scenario.provider,
            responseGenerationRequestIDOffset: scenario.requestIDOffset
        )
        let playbackService = FakeSequencerPlaybackService()
        let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: { playbackService },
            makeExternalMIDIPlaybackService: { _ in playbackService }
        )
        let service = AIPerformanceService(
            diagnosticsReporter: diagnosticsReporter,
            nowUptimeSeconds: { nowUptime },
            sleepFor: { _ in },
            discoveryOrchestrator: orchestrator,
            backendRegistry: ImprovBackendRegistry(backends: [backend]),
            selectedBackendKind: { selectedKind },
            aiPlaybackServiceFactory: { aiPlaybackFactory },
            onStateChanged: { states.append($0) }
        )
        defer { service.setEnabled(false) }

        let session = FakePracticeSession()
        service.updatePracticeSession(session)
        service.setEnabled(true)
        recordDuetTestPhrase(service)

        let expectedReason = "provider=network_bonjour_http_aria_v2;failure=invalid_response"
        for _ in 0 ..< 500 {
            await Task.yield()
            let events = await diagnosticsReporter.events
            if events.contains(where: { $0.reason == expectedReason }) { break }
        }

        #expect(playbackService.playCallCount == 0)
        #expect(states.last?.lastImprovStatusText?.contains("响应无效") == true)
        let events = await diagnosticsReporter.events
        #expect(events.contains(where: { $0.reason == expectedReason }))
    }
}

@Test
@MainActor
func responseLatencyQualityGateStopsSelectedBackend() async {
    let nowUptime: TimeInterval = 0
    var states: [AIPerformanceService.State] = []
    let diagnosticsReporter = InMemoryDiagnosticsReporter()
    let backendService = FakeBackendDiscoveryService()
    let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
    let selectedKind: ImprovBackendKind = .networkBonjourHTTPAriaV2
    let backend = FakeScheduleBackend(
        kind: selectedKind,
        schedule: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 90)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 72)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.3, kind: .noteOn(midi: 76, velocity: 88)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.5, kind: .noteOff(midi: 76)),
        ],
        backendLatencyMS: 400
    )
    let playbackService = FakeSequencerPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )
    let service = AIPerformanceService(
        diagnosticsReporter: diagnosticsReporter,
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { states.append($0) }
    )
    defer { service.setEnabled(false) }

    let session = FakePracticeSession()
    service.updatePracticeSession(session)
    service.setEnabled(true)
    recordDuetTestPhrase(service)

    let expectedReason = "provider=network_bonjour_http_aria_v2;failure=quality_gate;quality=responseLatency;latency=underOneSecond"
    for _ in 0 ..< 500 {
        await Task.yield()
        let events = await diagnosticsReporter.events
        if events.contains(where: { $0.reason == expectedReason }) { break }
    }

    #expect(playbackService.playCallCount == 0)
    #expect(states.last?.lastImprovStatusText?.contains("质量门拒绝") == true)
    let events = await diagnosticsReporter.events
    #expect(events.contains(where: { $0.reason == expectedReason }))
}

@Test
@MainActor
func observedResponseLatencyQualityGateStopsBackendWithoutReportedLatency() async {
    var states: [AIPerformanceService.State] = []
    let diagnosticsReporter = InMemoryDiagnosticsReporter()
    let backendService = FakeBackendDiscoveryService()
    let orchestrator = FakeDiscoveryOrchestrator(service: backendService)
    let selectedKind: ImprovBackendKind = .networkBonjourHTTPAriaV2
    let backend = FakeScheduleBackend(
        kind: selectedKind,
        schedule: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 90)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 72)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.3, kind: .noteOn(midi: 76, velocity: 88)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.5, kind: .noteOff(midi: 76)),
        ],
        responseDelay: .milliseconds(400)
    )
    let playbackService = FakeSequencerPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )
    let service = AIPerformanceService(
        diagnosticsReporter: diagnosticsReporter,
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { states.append($0) }
    )
    defer { service.setEnabled(false) }

    let session = FakePracticeSession()
    service.updatePracticeSession(session)
    service.setEnabled(true)
    let now = ProcessInfo.processInfo.systemUptime
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 90),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: .now,
            receivedAtUptimeSeconds: now
        )
    )

    try? await Task.sleep(for: .seconds(1))

    let expectedReason = "provider=network_bonjour_http_aria_v2;failure=quality_gate;quality=responseLatency;latency=underOneSecond"
    #expect(playbackService.playCallCount == 0)
    #expect(states.last?.lastImprovStatusText?.contains("质量门拒绝") == true)
    let events = await diagnosticsReporter.events
    #expect(events.contains(where: { $0.reason == expectedReason }))
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
    let backend = RecordingSeedBackend(kind: selectedKind, schedule: schedule)

    let playbackService = FakeSequencerPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
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
    let session = FakePracticeSession()
    service.updatePracticeSession(session)

    service.setEnabled(true)
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 90),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: Date(timeIntervalSince1970: 0),
            receivedAtUptimeSeconds: 0.0
        )
    )
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOff(note: 60, velocity: 0),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: nil),
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
        expectedBaseSeed &+ 0x9E37_79B9_7F4A_7C15,
        expectedBaseSeed &+ (2 &* 0x9E37_79B9_7F4A_7C15),
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
    let backend = RecordingSeedBackend(kind: selectedKind, schedule: schedule)

    let playbackService = FakeSequencerPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
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
    let session = FakePracticeSession()
    service.updatePracticeSession(session)

    service.setEnabled(true)
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 90),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: Date(timeIntervalSince1970: 0),
            receivedAtUptimeSeconds: 0.0
        )
    )
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOff(note: 60, velocity: 0),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: nil),
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
        ]
    )

    let playbackService = FakeSequencerPlaybackService()
    let aiPlaybackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )
    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { states.append($0) }
    )
    let session = FakePracticeSession()
    service.updatePracticeSession(session)

    service.setEnabled(true)
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 90),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: Date(timeIntervalSince1970: 0),
            receivedAtUptimeSeconds: 0.0
        )
    )
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOff(note: 60, velocity: 0),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: Date(timeIntervalSince1970: 0),
            receivedAtUptimeSeconds: 3.2
        )
    )

    for _ in 0 ..< 500 {
        await Task.yield()
        if playbackService.playCallCount > 0,
           states.last?.lastImprovStatusText?.contains("candidates=3") == true
        {
            break
        }
    }

    let latestSchedule = states.last?.latestSchedule ?? []
    let firstNoteOn = latestSchedule.first { if case .noteOn = $0.kind { true } else { false } }
    #expect(playbackService.playCallCount > 0)
    #expect(firstNoteOn != nil)
    if let firstNoteOn, case let .noteOn(midi, _) = firstNoteOn.kind {
        #expect(midi == 72)
    }
    #expect(states.last?.lastImprovStatusText?.contains("q=acceptable") == true)
    #expect(states.last?.lastImprovStatusText?.contains("candidates=3") == true)
}

@Test
@MainActor
func allRejectedCandidatesPreferSilenceWithRejectStatus() async {
    let nowUptime: TimeInterval = 0
    var states: [AIPerformanceService.State] = []
    let diagnosticsReporter = InMemoryDiagnosticsReporter()

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
        diagnosticsReporter: diagnosticsReporter,
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in },
        discoveryOrchestrator: orchestrator,
        backendRegistry: ImprovBackendRegistry(backends: [backend]),
        selectedBackendKind: { selectedKind },
        aiPlaybackServiceFactory: { aiPlaybackFactory },
        onStateChanged: { states.append($0) }
    )
    let session = FakePracticeSession()
    service.updatePracticeSession(session)

    service.setEnabled(true)
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOn(note: 60, velocity: 90),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: Date(timeIntervalSince1970: 0),
            receivedAtUptimeSeconds: 0.0
        )
    )
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: .noteOff(note: 60, velocity: 0),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .sourceIndex(0), endpointName: nil),
            receivedAt: Date(timeIntervalSince1970: 0),
            receivedAtUptimeSeconds: 3.2
        )
    )

    for _ in 0 ..< 500 {
        await Task.yield()
        let events = await diagnosticsReporter.events
        if events.contains(where: { $0.reason.hasPrefix("provider=local_rule;failure=quality_gate;quality=") }) { break }
    }

    #expect(playbackService.playCallCount == 0)
    #expect(states.last?.lastImprovStatusText?.contains("质量门拒绝") == true)
    let events = await diagnosticsReporter.events
    #expect(events.contains(where: { $0.reason.hasPrefix("provider=local_rule;failure=quality_gate;quality=") }))
}

@Test
func creativeDuetContractPreservesObservedInputAndGeneratedResponseProvenance() async throws {
    let events = [
        ImprovEvent.note(note: 60, velocity: 72, time: 0, duration: 0.4),
        ImprovEvent.cc(controller: 64, value: 127, time: 0.1),
    ]
    let observation = CreativeDuetPhraseProvenance.Observation(
        id: UUID(),
        source: .init(kind: .midi1, id: "creative-duet-test", generation: 1),
        timingProvenance: .hostOnly
    )
    let phrase = CreativeDuetPhrase(
        events: events,
        provenance: .init(observations: [observation])
    )
    let generation = CreativeDuetGeneration(
        requestID: 7,
        activationID: 3,
        seed: 42,
        sessionID: "test-session",
        parameters: ImprovGenerateParams(topP: 0.95, maxTokens: 12, strategy: "continuous", seed: 42)
    )
    let schedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 67, velocity: 88)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.3, kind: .noteOff(midi: 67)),
    ]
    let backend = FakeScheduleBackend(
        kind: .localRule,
        schedule: schedule,
        backendLatencyMS: 17
    )

    let response = try await backend.generateCreativeResponse(
        phrase: phrase,
        generation: generation,
        timeout: .seconds(1)
    )

    #expect(phrase.provenance.observations == [observation])
    #expect(phrase.provenance.observations.first?.capabilities == .midi)
    #expect(response.schedule == schedule)
    #expect(response.provider == .localRule)
    #expect(response.generation == generation)
    #expect(response.provenance == .backendGenerated(latencyMS: 17))
}
