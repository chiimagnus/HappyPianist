import Foundation

enum LayaNetworkCompanionDecisionBackendError: Error, Equatable {
    case backendNotResolved
    case discoveryDenied
    case discoveryFailed(message: String)
    case missingModelIdentity
    case missingActionAnswer
    case invalidAction(String)
}

private struct LayaCompanionNote: Encodable, Sendable {
    let midi: Int
    let velocity: Int
    let onsetSecondsAgo: TimeInterval
    let durationSeconds: TimeInterval

    enum CodingKeys: String, CodingKey {
        case midi
        case velocity
        case onsetSecondsAgo = "onset_seconds_ago"
        case durationSeconds = "duration_seconds"
    }
}

private struct LayaCompanionState: Encodable, Sendable {
    let heldNotesCount: Int
    let sustainValue: Int
    let recentIOIMedianSeconds: TimeInterval?
    let recentVelocityTrend: Double
    let recentNoteDensityPerSecond: Double
    let secondsSinceLastUserEvent: TimeInterval?
    let secondsSinceLastNoteOn: TimeInterval?
    let activePitchCenter: Double?
    let isAIPlaybackActive: Bool
    let recentNotes: [LayaCompanionNote]

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
        case recentNotes = "recent_notes"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(heldNotesCount, forKey: .heldNotesCount)
        try container.encode(sustainValue, forKey: .sustainValue)
        if let recentIOIMedianSeconds {
            try container.encode(recentIOIMedianSeconds, forKey: .recentIOIMedianSeconds)
        } else {
            try container.encodeNil(forKey: .recentIOIMedianSeconds)
        }
        try container.encode(recentVelocityTrend, forKey: .recentVelocityTrend)
        try container.encode(recentNoteDensityPerSecond, forKey: .recentNoteDensityPerSecond)
        if let secondsSinceLastUserEvent {
            try container.encode(secondsSinceLastUserEvent, forKey: .secondsSinceLastUserEvent)
        } else {
            try container.encodeNil(forKey: .secondsSinceLastUserEvent)
        }
        if let secondsSinceLastNoteOn {
            try container.encode(secondsSinceLastNoteOn, forKey: .secondsSinceLastNoteOn)
        } else {
            try container.encodeNil(forKey: .secondsSinceLastNoteOn)
        }
        if let activePitchCenter {
            try container.encode(activePitchCenter, forKey: .activePitchCenter)
        } else {
            try container.encodeNil(forKey: .activePitchCenter)
        }
        try container.encode(isAIPlaybackActive, forKey: .isAIPlaybackActive)
        try container.encode(recentNotes, forKey: .recentNotes)
    }
}

actor LayaNetworkCompanionDecisionBackend: CompanionDecisionBackendProtocol {
    nonisolated let kind: CompanionDecisionBackendKind = .networkBonjourLaya
    nonisolated let displayName = "Laya-MLX 分类器（Mac 本地，实验）"

    private static let actionQuestion: LayaQuestion = .choice(
        instructions: """
        Choose the single piano companion action that best matches the observable MIDI state. Do not infer an ending from a short breath while notes or sustain remain active.
        """,
        criteria: [
            "listen": "The user is actively playing, holding notes, sustaining, or only taking a brief musical breath. The AI should stay silent and keep listening.",
            "support": "The user is still playing and the texture is sparse and stable enough for light supportive accompaniment without taking the lead.",
            "sparse": "The user is still active and there is only limited room for accompaniment. If the AI joins, it should contribute very few notes.",
            "yield": "The AI is currently playing and the user has clearly re-entered or reasserted control. The AI should stop adding future notes and yield immediately.",
            "respond": "The user's phrase has clearly ended: no held notes, sustain is released, and a clear gap has formed. The AI should answer the completed phrase.",
        ]
    )

    private let discoveryService: any BonjourBackendDiscoveryServiceProtocol
    private let client: any LayaClassifierClientProtocol
    private let discoveryTimeout: Duration
    private let requestTimeoutSeconds: TimeInterval

    init(
        discoveryService: any BonjourBackendDiscoveryServiceProtocol,
        client: any LayaClassifierClientProtocol = LayaClassifierClient(),
        discoveryTimeout: Duration = .seconds(1),
        requestTimeoutSeconds: TimeInterval = 1
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
            questions: ["action": Self.actionQuestion],
            timeoutSeconds: requestTimeoutSeconds
        )
        guard let rawAnswer = response.answers["action"] else {
            throw LayaNetworkCompanionDecisionBackendError.missingActionAnswer
        }
        guard case let .choice(answer) = rawAnswer else {
            throw LayaNetworkCompanionDecisionBackendError.missingActionAnswer
        }
        guard let action = CompanionAction(rawValue: answer.choice) else {
            throw LayaNetworkCompanionDecisionBackendError.invalidAction(answer.choice)
        }
        return CompanionDecision(
            action: action,
            confidence: answer.confidence
        )
    }

    private func makeState(_ input: CompanionDecisionInput) -> LayaCompanionState {
        func elapsed(since timestamp: TimeInterval?) -> TimeInterval? {
            timestamp.map { max(0, input.nowTimestampSeconds - $0) }
        }

        return LayaCompanionState(
            heldNotesCount: input.heldNotesCount,
            sustainValue: input.sustainValue,
            recentIOIMedianSeconds: input.recentIOIMedianSeconds,
            recentVelocityTrend: input.recentVelocityTrend,
            recentNoteDensityPerSecond: input.recentNoteDensityPerSecond,
            secondsSinceLastUserEvent: elapsed(since: input.lastUserEventTimestampSeconds),
            secondsSinceLastNoteOn: elapsed(since: input.lastNoteOnTimestampSeconds),
            activePitchCenter: input.activePitchCenter,
            isAIPlaybackActive: input.isAIPlaybackActive,
            recentNotes: input.recentNotes.map {
                LayaCompanionNote(
                    midi: $0.midi,
                    velocity: $0.velocity,
                    onsetSecondsAgo: $0.onsetSecondsAgo,
                    durationSeconds: $0.durationSeconds
                )
            }
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
                    throw LayaNetworkCompanionDecisionBackendError.missingModelIdentity
                }
                return (host, port, model)
            case .denied:
                throw LayaNetworkCompanionDecisionBackendError.discoveryDenied
            case let .failed(message):
                throw LayaNetworkCompanionDecisionBackendError.discoveryFailed(message: message)
            case .idle, .discovering:
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        throw LayaNetworkCompanionDecisionBackendError.backendNotResolved
    }
}
