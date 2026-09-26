import Foundation

enum QwenNetworkCompanionDecisionBackendError: Error, Equatable {
    case backendNotResolved
    case discoveryDenied
    case discoveryFailed(message: String)
    case missingModelIdentity
    case missingSemanticAnswer(String)
    case invalidSemanticAnswer(String)
}

private struct QwenCompanionState: Encodable, Sendable {
    let heldNotesCount: Int
    let sustainValue: Int
    let recentIOIMedianSeconds: TimeInterval?
    let recentVelocityTrend: Double
    let recentNoteDensityPerSecond: Double
    let secondsSinceLastUserEvent: TimeInterval?
    let secondsSinceLastNoteOn: TimeInterval?
    let activePitchCenter: Double?
    let isAIPlaybackActive: Bool

    enum CodingKeys: String, CodingKey {
        case heldNotesCount = "held_notes_count"
        case sustainValue = "sustain_value"
        case recentIOIMedianSeconds = "recent_ioi_median_seconds"
        case recentVelocityTrend = "recent_velocity_trend"
        case recentNoteDensityPerSecond = "recent_note_density_per_second"
        case secondsSinceLastUserEvent = "seconds_since_last_user_event"
        case secondsSinceLastNoteOn = "seconds_since_last_note_on"
        case activePitchCenter = "active_pitch_center"
        case isAIPlaybackActive = "is_ai_playback_active"
    }
}

private struct QwenSemanticRule: Sendable {
    let instructions: String
    let trueCriteria: String
    let falseCriteria: String
}

private struct QwenSemanticScores: Sendable {
    let continuing: Double
    let finished: Double
    let space: Double
    let reasserted: Double
}

actor QwenNetworkCompanionDecisionBackend: CompanionDecisionBackendProtocol {
    nonisolated let kind: CompanionDecisionBackendKind = .networkBonjourQwen
    nonisolated let displayName = "Qwen3.5-0.8B（电脑本地，实验）"

    private static let semanticThreshold = 0.55
    private static let sparseDensityThreshold = 2.0

    private static let semanticRules: [String: QwenSemanticRule] = [
        "continuing": QwenSemanticRule(
            instructions: "Binary decision from the JSON state: is the pianist still continuing the current phrase?",
            trueCriteria: "true when held_notes_count > 0, OR sustain_value >= 64, OR seconds_since_last_note_on < 0.50.",
            falseCriteria: "false when held_notes_count == 0, sustain_value < 64, AND seconds_since_last_note_on >= 0.75."
        ),
        "finished": QwenSemanticRule(
            instructions: "Binary decision from the JSON state: has the pianist clearly finished the current phrase?",
            trueCriteria: "true only when held_notes_count == 0, sustain_value < 64, AND seconds_since_last_note_on >= 0.75.",
            falseCriteria: "false when held_notes_count > 0, OR sustain_value >= 64, OR seconds_since_last_note_on < 0.50."
        ),
        "space": QwenSemanticRule(
            instructions: "Binary decision from the JSON state: while the pianist is still active, is there room for light accompaniment?",
            trueCriteria: "true when the phrase is still active and recent_note_density_per_second < 2.0; a longer recent_ioi_median_seconds also supports room for light accompaniment.",
            falseCriteria: "false when the phrase has finished, OR recent_note_density_per_second >= 2.0 with continuous active playing."
        ),
        "reasserted": QwenSemanticRule(
            instructions: "Binary decision from the JSON state: while AI playback is active, has the pianist reasserted control?",
            trueCriteria: "true only when is_ai_playback_active == true AND the pianist has recent active input: held_notes_count > 0, OR seconds_since_last_note_on < 0.50, OR recent_note_density_per_second >= 2.0.",
            falseCriteria: "false whenever is_ai_playback_active == false. This condition is mandatory."
        ),
    ]

    private let discoveryService: any BonjourBackendDiscoveryServiceProtocol
    private let client: any QwenClassifierClientProtocol
    private let discoveryTimeout: Duration
    private let requestTimeoutSeconds: TimeInterval

    init(
        discoveryService: any BonjourBackendDiscoveryServiceProtocol,
        client: any QwenClassifierClientProtocol = QwenClassifierClient(),
        discoveryTimeout: Duration = .seconds(1),
        requestTimeoutSeconds: TimeInterval = 1.5
    ) {
        self.discoveryService = discoveryService
        self.client = client
        self.discoveryTimeout = discoveryTimeout
        self.requestTimeoutSeconds = requestTimeoutSeconds
    }

    func decide(_ input: CompanionDecisionInput) async throws -> CompanionDecision {
        await MainActor.run {
            switch discoveryService.state {
            case .idle, .failed:
                discoveryService.start()
            case .discovering, .resolved, .denied:
                break
            }
        }

        let endpoint = try await waitForResolvedEndpoint()
        let response = try await client.classify(
            host: endpoint.host,
            port: endpoint.port,
            model: endpoint.model,
            state: makeState(input),
            questions: Self.makeQuestions(),
            timeoutSeconds: requestTimeoutSeconds
        )
        let scores = try Self.semanticScores(from: response)
        return CompanionDecision(
            action: Self.action(for: input, scores: scores)
        )
    }

    private static func makeQuestions() -> [String: QwenQuestion] {
        var questions: [String: QwenQuestion] = [:]
        for (semantic, rule) in semanticRules {
            questions["\(semantic)__true_a"] = .choice(
                instructions: rule.instructions,
                criteria: [
                    "A": rule.trueCriteria,
                    "B": rule.falseCriteria,
                ]
            )
            questions["\(semantic)__true_b"] = .choice(
                instructions: rule.instructions,
                criteria: [
                    "A": rule.falseCriteria,
                    "B": rule.trueCriteria,
                ]
            )
        }
        return questions
    }

    private static func semanticScores(
        from response: QwenClassifierResponse
    ) throws -> QwenSemanticScores {
        func trueProbability(_ semantic: String, variant: String, trueLabel: String) throws -> Double {
            let questionID = "\(semantic)__\(variant)"
            guard let rawAnswer = response.answers[questionID] else {
                throw QwenNetworkCompanionDecisionBackendError.missingSemanticAnswer(questionID)
            }
            guard case let .choice(answer) = rawAnswer,
                  ["A", "B"].contains(answer.choice),
                  Set(answer.probabilities.keys) == Set(["A", "B"]),
                  let a = answer.probabilities["A"],
                  let b = answer.probabilities["B"],
                  (0 ... 1).contains(a),
                  (0 ... 1).contains(b),
                  abs(a + b - 1) <= 1e-4,
                  let probability = answer.probabilities[trueLabel]
            else {
                throw QwenNetworkCompanionDecisionBackendError.invalidSemanticAnswer(questionID)
            }
            return probability
        }

        func score(_ semantic: String) throws -> Double {
            let trueOnA = try trueProbability(semantic, variant: "true_a", trueLabel: "A")
            let trueOnB = try trueProbability(semantic, variant: "true_b", trueLabel: "B")
            return (trueOnA + trueOnB) / 2
        }

        return try QwenSemanticScores(
            continuing: score("continuing"),
            finished: score("finished"),
            space: score("space"),
            reasserted: score("reasserted")
        )
    }

    private static func action(
        for input: CompanionDecisionInput,
        scores: QwenSemanticScores
    ) -> CompanionAction {
        if input.isAIPlaybackActive, scores.reasserted >= semanticThreshold {
            return .yield
        }
        if scores.finished >= semanticThreshold, scores.continuing < semanticThreshold {
            return .respond
        }
        if scores.continuing < semanticThreshold || scores.space < semanticThreshold {
            return .listen
        }
        return input.recentNoteDensityPerSecond >= sparseDensityThreshold ? .sparse : .support
    }

    private func makeState(_ input: CompanionDecisionInput) -> QwenCompanionState {
        func elapsed(since timestamp: TimeInterval?) -> TimeInterval? {
            timestamp.map { max(0, input.nowTimestampSeconds - $0) }
        }

        return QwenCompanionState(
            heldNotesCount: input.heldNotesCount,
            sustainValue: input.sustainValue,
            recentIOIMedianSeconds: input.recentIOIMedianSeconds,
            recentVelocityTrend: input.recentVelocityTrend,
            recentNoteDensityPerSecond: input.recentNoteDensityPerSecond,
            secondsSinceLastUserEvent: elapsed(since: input.lastUserEventTimestampSeconds),
            secondsSinceLastNoteOn: elapsed(since: input.lastNoteOnTimestampSeconds),
            activePitchCenter: input.activePitchCenter,
            isAIPlaybackActive: input.isAIPlaybackActive
        )
    }

    private func waitForResolvedEndpoint() async throws -> (
        host: String,
        port: Int,
        model: String
    ) {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: discoveryTimeout)

        while clock.now < deadline, Task.isCancelled == false {
            let state = await MainActor.run { discoveryService.state }
            switch state {
            case let .resolved(host, port, txtRecord):
                guard let model = txtRecord["engine_impl"], model.isEmpty == false else {
                    throw QwenNetworkCompanionDecisionBackendError.missingModelIdentity
                }
                return (host, port, model)
            case .denied:
                throw QwenNetworkCompanionDecisionBackendError.discoveryDenied
            case let .failed(message):
                throw QwenNetworkCompanionDecisionBackendError.discoveryFailed(message: message)
            case .idle, .discovering:
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        throw QwenNetworkCompanionDecisionBackendError.backendNotResolved
    }
}
