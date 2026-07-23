import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
private final class ResolvedBackendDiscoveryService: BonjourBackendDiscoveryServiceProtocol {
    let state: BonjourBackendDiscoveryService.State

    init(host: String, port: Int, txtRecord: [String: String] = [:]) {
        state = .resolved(host: host, port: port, txtRecord: txtRecord)
    }

    func start() {}
    func stop() {}
}

private actor FixedHTTPBackendClient: ImprovBackendClientProtocol {
    private let result: ImprovResultResponseV2
    private var requests: [ImprovGenerateRequestV2] = []

    init(result: ImprovResultResponseV2) {
        self.result = result
    }

    func generateV2(
        host _: String,
        port _: Int,
        request: ImprovGenerateRequestV2,
        timeoutSeconds _: TimeInterval
    ) async throws -> ImprovResultResponseV2 {
        requests.append(request)
        return result
    }

    func receivedRequests() -> [ImprovGenerateRequestV2] {
        requests
    }
}

private actor FixedStreamingBackendClient: ImprovStreamingClientProtocol {
    private let chunks: [ImprovStreamChunkV2]
    private var starts: [ImprovStreamStartRequestV2] = []

    init(chunks: [ImprovStreamChunkV2]) {
        self.chunks = chunks
    }

    func streamChunks(
        url _: URL,
        start: ImprovStreamStartRequestV2,
        timeout _: Duration
    ) async throws -> AsyncThrowingStream<ImprovStreamChunkV2, Error> {
        starts.append(start)
        let chunks = self.chunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    func receivedStarts() -> [ImprovStreamStartRequestV2] {
        starts
    }
}

@Test
func improvScheduleBuilderSortsAndGeneratesNoteOff() {
    let notes = [
        ImprovDialogueNote(note: 64, velocity: 90, time: 0.4, duration: 0.2),
        ImprovDialogueNote(note: 60, velocity: 90, time: 0.0, duration: 0.1),
        ImprovDialogueNote(note: 67, velocity: 90, time: 0.2, duration: 0.1),
    ]

    let builder = ImprovScheduleBuilder()
    let schedule = builder.buildSchedule(from: notes, leadInSeconds: 0)
    #expect(schedule.count == 6)
    #expect(abs(schedule[0].timeSeconds - 0.0) < 0.0001)
    // A.I. Duet: reply note durations are shortened to 90% (see `ImprovScheduleBuilder`).
    #expect(abs(schedule[5].timeSeconds - 0.58) < 0.0001)
}

@Test
func improvScheduleBuilderClampsDuration() {
    let notes = [
        ImprovDialogueNote(note: 60, velocity: 90, time: 0.0, duration: -1.0),
    ]
    let builder = ImprovScheduleBuilder()
    let schedule = builder.buildSchedule(from: notes, leadInSeconds: 0)
    #expect(schedule.count == 2)
    #expect(schedule[0].timeSeconds == 0.0)
    #expect(schedule[1].timeSeconds >= 0.05)
}

@Test
func improvScheduleBuilderNegativeTimeStillProducesDuration() {
    let notes = [
        ImprovDialogueNote(note: 60, velocity: 90, time: -1.0, duration: 0.2),
    ]
    let builder = ImprovScheduleBuilder()
    let schedule = builder.buildSchedule(from: notes, leadInSeconds: 0)
    #expect(schedule.count == 2)
    #expect(schedule[0].timeSeconds == 0.0)
    #expect(schedule[1].timeSeconds >= 0.18)
}

@Test
func improvScheduleBuilderEmptyNotesIsEmptySchedule() {
    let builder = ImprovScheduleBuilder()
    #expect(builder.buildSchedule(from: [ImprovDialogueNote](), leadInSeconds: 0).isEmpty)
}

@Test
func localRuleBackendQualityCorpusUsesNativeCreativeResponse() async throws {
    let rule = DuetQualityRegressionFixtures.ruleQualityCorpus
    #expect(rule.provider == .localRule)
    #expect(rule.parameters.seed == .some(rule.seed))
    #expect(rule.parameters.strategy == "deterministic")
    guard case .generatedRule = rule.response else {
        Issue.record("Rule corpus must generate from its fixed seed.")
        return
    }

    let generation = rule.creativeGeneration
    let response = try await LocalRuleImprovBackend().generateCreativeResponse(
        phrase: rule.creativePhrase,
        generation: generation,
        timeout: .seconds(1)
    )

    #expect(response.provider == rule.provider)
    #expect(response.generation == generation)
    #expect(response.provenance == .backendGenerated(latencyMS: nil))
    #expect(response.schedule.isEmpty == false)
    #expect(ImprovQualityRubric().assess(response.schedule).band == rule.expectedBand)
}

@Test
@MainActor
func ariaHTTPBackendQualityCorpusUsesNativeCreativeResponse() async throws {
    let network = DuetQualityRegressionFixtures.networkFakeQualityCorpus
    #expect(network.provider == .networkBonjourHTTPAriaV2)
    #expect(network.parameters.seed == .some(network.seed))
    #expect(network.parameters.strategy == "network")
    guard case let .networkFakeEvents(events) = network.response else {
        Issue.record("Network corpus must use a protocol response fake.")
        return
    }

    let client = FixedHTTPBackendClient(
        result: ImprovResultResponseV2(
            type: "result",
            protocolVersion: 2,
            events: events,
            latencyMS: 23
        )
    )
    let backend = AriaNetworkBonjourHTTPImprovBackend(
        discoveryService: ResolvedBackendDiscoveryService(host: "127.0.0.1", port: 8766),
        backendClient: client
    )
    let generation = network.creativeGeneration
    let response = try await backend.generateCreativeResponse(
        phrase: network.creativePhrase,
        generation: generation,
        timeout: .seconds(1)
    )

    #expect(response.provider == network.provider)
    #expect(response.generation == generation)
    #expect(response.provenance == .backendGenerated(latencyMS: 23))
    #expect(response.schedule.isEmpty == false)
    #expect(ImprovQualityRubric().assess(response.schedule).band == network.expectedBand)
    let requests = await client.receivedRequests()
    #expect(requests.count == 1)
    #expect(requests.first?.events == network.creativePhrase.events)
    #expect(requests.first?.params == network.parameters)
}

@Test
@MainActor
func ariaWebSocketBackendQualityCorpusUsesNativeCreativeResponse() async throws {
    let network = DuetQualityRegressionFixtures.networkWebSocketFakeQualityCorpus
    #expect(network.provider == .networkBonjourWebSocketAriaV2)
    guard case let .networkFakeEvents(events) = network.response else {
        Issue.record("WebSocket corpus must use a protocol response fake.")
        return
    }

    let client = FixedStreamingBackendClient(chunks: [
        ImprovStreamChunkV2(
            seq: 0,
            isFinal: true,
            timeRange: .init(start: 0, end: 0.5),
            events: events
        ),
    ])
    let backend = AriaNetworkBonjourWebSocketImprovBackend(
        discoveryService: ResolvedBackendDiscoveryService(
            host: "127.0.0.1",
            port: 8766,
            txtRecord: ["ws_path": "/stream"]
        ),
        streamingClient: client
    )
    let generation = network.creativeGeneration
    let response = try await backend.generateCreativeResponse(
        phrase: network.creativePhrase,
        generation: generation,
        timeout: .seconds(1)
    )

    #expect(response.provider == network.provider)
    #expect(response.generation == generation)
    #expect(response.provenance == .backendGenerated(latencyMS: nil))
    #expect(response.schedule.isEmpty == false)
    #expect(ImprovQualityRubric().assess(response.schedule).band == network.expectedBand)
    let starts = await client.receivedStarts()
    #expect(starts.count == 1)
    #expect(starts.first?.request.events == network.creativePhrase.events)
    #expect(starts.first?.request.params == network.parameters)
}
