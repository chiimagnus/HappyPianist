import Foundation
import Practice
@testable import HappyPianistAVP
import Testing

@MainActor
private final class ResolvedBackendDiscoveryService: BonjourBackendDiscoveryServiceProtocol {
    var state: BonjourBackendDiscoveryService.State

    init(host: String, port: Int) {
        state = .resolved(host: host, port: port, txtRecord: [:])
    }

    func start() {}
    func stop() {}
}

@MainActor
private final class DelayedBackendDiscoveryService: BonjourBackendDiscoveryServiceProtocol {
    var state: BonjourBackendDiscoveryService.State = .discovering

    func start() {}
    func stop() {}

    func resolve(host: String = "127.0.0.1", port: Int = 8766) {
        state = .resolved(host: host, port: port, txtRecord: [:])
    }
}

private actor FixedHTTPBackendClient: ImprovBackendClientProtocol {
    private let result: AriaResultResponse
    private var requests: [AriaGenerateRequest] = []
    private var timeouts: [TimeInterval] = []

    init(result: AriaResultResponse) {
        self.result = result
    }

    func generate(
        host _: String,
        port _: Int,
        request: AriaGenerateRequest,
        timeoutSeconds: TimeInterval
    ) async throws -> AriaResultResponse {
        requests.append(request)
        timeouts.append(timeoutSeconds)
        return result
    }

    func receivedRequests() -> [AriaGenerateRequest] { requests }
    func receivedTimeouts() -> [TimeInterval] { timeouts }
}

@Test
func improvScheduleBuilderSortsAndGeneratesNoteOff() {
    let notes = [
        ImprovDialogueNote(note: 64, velocity: 90, time: 0.4, duration: 0.2),
        ImprovDialogueNote(note: 60, velocity: 90, time: 0.0, duration: 0.1),
        ImprovDialogueNote(note: 67, velocity: 90, time: 0.2, duration: 0.1),
    ]

    let schedule = ImprovScheduleBuilder().buildSchedule(from: notes, leadInSeconds: 0)
    #expect(schedule.count == 6)
    #expect(abs(schedule[0].timeSeconds - 0.0) < 0.0001)
    #expect(abs(schedule[5].timeSeconds - 0.58) < 0.0001)
}

@Test
func improvScheduleBuilderKeepsIntentionalMinimumPlayableDuration() {
    let notes = [
        ImprovDialogueNote(note: 60, velocity: 90, time: 0.0, duration: 0.01),
    ]
    let schedule = ImprovScheduleBuilder().buildSchedule(from: notes, leadInSeconds: 0)
    #expect(schedule.count == 2)
    #expect(schedule[0].timeSeconds == 0.0)
    #expect(abs(schedule[1].timeSeconds - 0.05) < 0.0001)
}

@Test
func improvScheduleBuilderEmptyNotesIsEmptySchedule() {
    #expect(ImprovScheduleBuilder().buildSchedule(from: [ImprovDialogueNote](), leadInSeconds: 0).isEmpty)
}

@Test
func localRuleBackendQualityCorpusUsesNativeCreativeResponse() async throws {
    let rule = DuetQualityRegressionFixtures.ruleQualityCorpus
    #expect(rule.provider == .localRule)
    #expect(rule.parameters.seed == rule.seed)
    guard case .generatedRule = rule.response else {
        Issue.record("Rule corpus must generate from its fixed seed.")
        return
    }

    let generation = rule.creativeGeneration
    let response = try await LocalRuleImprovBackend().generateCreativeResponse(
        phrase: rule.creativePhrase,
        generation: generation
    )

    #expect(response.provider == rule.provider)
    #expect(response.generation == generation)
    #expect(response.provenance == .backendGenerated(latencyMS: nil))
    #expect(response.schedule.isEmpty == false)
    #expect(ImprovQualityRubric().assess(response.schedule).band == rule.expectedBand)
}

@Test
@MainActor
func ariaHTTPBackendQualityCorpusUsesCurrentNetworkContract() async throws {
    let network = DuetQualityRegressionFixtures.networkFakeQualityCorpus
    #expect(network.provider == .networkBonjourHTTPAria)
    #expect(network.parameters.seed == network.seed)
    guard case let .networkFakeEvents(events) = network.response else {
        Issue.record("Network corpus must use a protocol response fake.")
        return
    }

    let client = FixedHTTPBackendClient(
        result: AriaResultResponse(events: events, latencyMS: 23)
    )
    let backend = AriaNetworkBonjourHTTPImprovBackend(
        discoveryService: ResolvedBackendDiscoveryService(host: "127.0.0.1", port: 8766),
        backendClient: client
    )
    let generation = network.creativeGeneration
    let response = try await backend.generateCreativeResponse(
        phrase: network.creativePhrase,
        generation: generation
    )

    #expect(response.provider == network.provider)
    #expect(response.generation == generation)
    #expect(response.provenance == .backendGenerated(latencyMS: 23))
    #expect(response.schedule.isEmpty == false)
    #expect(ImprovQualityRubric().assess(response.schedule).band == network.expectedBand)
    let requests = await client.receivedRequests()
    #expect(requests.count == 1)
    #expect(requests.first?.events == network.creativePhrase.events)
    #expect(requests.first?.params.maxTokens == network.parameters.maxTokens)
}

@Test
@MainActor
func ariaHTTPBackendSharesOne350MillisecondDeadlineAcrossDiscoveryAndRequest() async throws {
    let discovery = DelayedBackendDiscoveryService()
    let client = FixedHTTPBackendClient(
        result: AriaResultResponse(
            events: [.note(note: 67, velocity: 88, time: 0, duration: 0.2)],
            latencyMS: 1
        )
    )
    let backend = AriaNetworkBonjourHTTPImprovBackend(
        discoveryService: discovery,
        backendClient: client
    )
    let phrase = CreativeDuetPhrase(
        events: [.note(note: 60, velocity: 90, time: 0, duration: 0.2)],
        provenance: .empty
    )
    let generation = CreativeDuetGeneration(
        requestID: 1,
        activationID: 1,
        parameters: .init(topP: 0.95, maxTokens: 64, seed: 1)
    )

    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(80))
        discovery.resolve()
    }

    _ = try await backend.generateCreativeResponse(phrase: phrase, generation: generation)

    let timeout = try #require(await client.receivedTimeouts().first)
    #expect(timeout > 0)
    #expect(timeout < ImprovQualityRubric.Thresholds.v2.maximumResponseLatencySeconds - 0.04)
}
