import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
private final class StubQwenDiscoveryService: BonjourBackendDiscoveryServiceProtocol {
    var state: BonjourBackendDiscoveryService.State
    private(set) var startCount = 0

    init(state: BonjourBackendDiscoveryService.State) {
        self.state = state
    }

    func start() { startCount += 1 }
    func stop() {}
}

private actor RecordingQwenClassifierClient: QwenClassifierClientProtocol {
    struct Call: Sendable {
        let host: String
        let port: Int
        let model: String
        let stateData: Data
        let questions: [String: QwenQuestion]
        let timeoutSeconds: TimeInterval
    }

    private let response: QwenClassifierResponse
    private var call: Call?

    init(response: QwenClassifierResponse) {
        self.response = response
    }

    func classify<State: Encodable & Sendable>(
        host: String,
        port: Int,
        model: String,
        state: State,
        questions: [String: QwenQuestion],
        timeoutSeconds: TimeInterval
    ) async throws -> QwenClassifierResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        call = Call(
            host: host,
            port: port,
            model: model,
            stateData: try encoder.encode(state),
            questions: questions,
            timeoutSeconds: timeoutSeconds
        )
        return response
    }

    func recordedCall() -> Call? { call }
}

@Test @MainActor
func qwenCompanionBackendUsesUnifiedSemanticProtocolAndMapsRespond() async throws {
    let model = "Qwen/Qwen3.5-0.8B"
    let discovery = StubQwenDiscoveryService(
        state: .resolved(
            host: "windows.local",
            port: 8767,
            txtRecord: [
                "engine": "qwen-classifier",
                "engine_impl": model,
            ]
        )
    )
    let client = RecordingQwenClassifierClient(
        response: qwenSemanticResponse(
            model: model,
            scores: [
                "continuing": 0.30,
                "finished": 0.80,
                "space": 0.20,
                "reasserted": 0.20,
            ]
        )
    )
    let backend = QwenNetworkCompanionDecisionBackend(
        discoveryService: discovery,
        client: client,
        requestTimeoutSeconds: 1.5
    )

    let decision = try await backend.decide(qwenTestInput(density: 0, aiPlaybackActive: false))

    #expect(decision == CompanionDecision(action: .respond))
    let call = try #require(await client.recordedCall())
    #expect(call.host == "windows.local")
    #expect(call.port == 8767)
    #expect(call.model == model)
    #expect(call.timeoutSeconds == 1.5)
    #expect(call.questions.count == 8)

    let state = try #require(JSONSerialization.jsonObject(with: call.stateData) as? [String: Any])
    #expect(state["held_notes_count"] as? Int == 0)
    #expect(state["sustain_value"] as? Int == 0)
    #expect(state["recent_note_density_per_second"] as? Double == 0)
    #expect(state["is_ai_playback_active"] as? Bool == false)
    #expect(state["recent_notes"] == nil)

    let trueA = try #require(call.questions["finished__true_a"])
    let trueB = try #require(call.questions["finished__true_b"])
    #expect(trueA.criteria["A"]?.contains("held_notes_count == 0") == true)
    #expect(trueA.criteria["B"]?.contains("held_notes_count > 0") == true)
    #expect(trueA.criteria["A"] == trueB.criteria["B"])
    #expect(trueA.criteria["B"] == trueB.criteria["A"])
}

@Test @MainActor
func qwenCompanionBackendAppliesSemanticV1ActionPriority() async throws {
    let model = "Qwen/Qwen3.5-0.8B"
    let discovery = StubQwenDiscoveryService(
        state: .resolved(host: "windows.local", port: 8767, txtRecord: ["engine_impl": model])
    )

    let yieldBackend = QwenNetworkCompanionDecisionBackend(
        discoveryService: discovery,
        client: RecordingQwenClassifierClient(
            response: qwenSemanticResponse(
                model: model,
                scores: ["continuing": 0.9, "finished": 0.1, "space": 0.1, "reasserted": 0.8]
            )
        )
    )
    #expect(
        try await yieldBackend.decide(qwenTestInput(density: 4, aiPlaybackActive: true))
            == CompanionDecision(action: .yield)
    )

    let listenBackend = QwenNetworkCompanionDecisionBackend(
        discoveryService: discovery,
        client: RecordingQwenClassifierClient(
            response: qwenSemanticResponse(
                model: model,
                scores: ["continuing": 0.9, "finished": 0.1, "space": 0.4, "reasserted": 0.1]
            )
        )
    )
    #expect(
        try await listenBackend.decide(qwenTestInput(density: 4, aiPlaybackActive: false))
            == CompanionDecision(action: .listen)
    )

    let supportBackend = QwenNetworkCompanionDecisionBackend(
        discoveryService: discovery,
        client: RecordingQwenClassifierClient(
            response: qwenSemanticResponse(
                model: model,
                scores: ["continuing": 0.9, "finished": 0.1, "space": 0.9, "reasserted": 0.1]
            )
        )
    )
    #expect(
        try await supportBackend.decide(qwenTestInput(density: 1, aiPlaybackActive: false))
            == CompanionDecision(action: .support)
    )

    let sparseBackend = QwenNetworkCompanionDecisionBackend(
        discoveryService: discovery,
        client: RecordingQwenClassifierClient(
            response: qwenSemanticResponse(
                model: model,
                scores: ["continuing": 0.9, "finished": 0.1, "space": 0.9, "reasserted": 0.1]
            )
        )
    )
    #expect(
        try await sparseBackend.decide(qwenTestInput(density: 2, aiPlaybackActive: false))
            == CompanionDecision(action: .sparse)
    )
}

@Test @MainActor
func qwenCompanionBackendRejectsIncompleteSemanticResponseWithoutFallback() async throws {
    let model = "Qwen/Qwen3.5-0.8B"
    let discovery = StubQwenDiscoveryService(
        state: .resolved(host: "windows.local", port: 8767, txtRecord: ["engine_impl": model])
    )
    var response = qwenSemanticResponse(
        model: model,
        scores: ["continuing": 0.8, "finished": 0.2, "space": 0.2, "reasserted": 0.2]
    )
    response = QwenClassifierResponse(
        model: response.model,
        answers: response.answers.filter { $0.key != "finished__true_b" },
        usage: response.usage,
        latencyMS: response.latencyMS
    )
    let backend = QwenNetworkCompanionDecisionBackend(
        discoveryService: discovery,
        client: RecordingQwenClassifierClient(response: response)
    )

    await #expect(throws: QwenNetworkCompanionDecisionBackendError.missingSemanticAnswer("finished__true_b")) {
        _ = try await backend.decide(qwenTestInput(density: 4, aiPlaybackActive: false))
    }
}

@Test @MainActor
func qwenCompanionBackendReportsDiscoveryDenialWithoutRuleFallback() async throws {
    let discovery = StubQwenDiscoveryService(state: .denied)
    let client = RecordingQwenClassifierClient(
        response: qwenSemanticResponse(
            model: "Qwen/Qwen3.5-0.8B",
            scores: ["continuing": 0.8, "finished": 0.2, "space": 0.2, "reasserted": 0.2]
        )
    )
    let backend = QwenNetworkCompanionDecisionBackend(discoveryService: discovery, client: client)

    await #expect(throws: QwenNetworkCompanionDecisionBackendError.discoveryDenied) {
        _ = try await backend.decide(qwenTestInput(density: 4, aiPlaybackActive: false))
    }
    #expect(await client.recordedCall() == nil)
}

private func qwenSemanticResponse(
    model: String,
    scores: [String: Double]
) -> QwenClassifierResponse {
    var answers: [String: QwenAnswer] = [:]
    for semantic in ["continuing", "finished", "space", "reasserted"] {
        let score = scores[semantic] ?? 0.5
        answers["\(semantic)__true_a"] = .choice(
            QwenChoiceAnswer(
                choice: score >= 0.5 ? "A" : "B",
                confidence: max(score, 1 - score),
                probabilities: ["A": score, "B": 1 - score]
            )
        )
        answers["\(semantic)__true_b"] = .choice(
            QwenChoiceAnswer(
                choice: score >= 0.5 ? "B" : "A",
                confidence: max(score, 1 - score),
                probabilities: ["A": 1 - score, "B": score]
            )
        )
    }
    return QwenClassifierResponse(
        model: model,
        answers: answers,
        usage: QwenClassifierUsage(inputTokens: 120, outputTokens: 0),
        latencyMS: 1100
    )
}

private func qwenTestInput(
    density: Double,
    aiPlaybackActive: Bool
) -> CompanionDecisionInput {
    CompanionDecisionInput(
        nowTimestampSeconds: 100,
        heldNotesCount: 0,
        sustainValue: 0,
        recentIOIMedianSeconds: 0.42,
        recentVelocityTrend: -1.5,
        recentNoteDensityPerSecond: density,
        lastUserEventTimestampSeconds: 98.8,
        lastNoteOnTimestampSeconds: 98.5,
        activePitchCenter: nil,
        isAIPlaybackActive: aiPlaybackActive
    )
}
