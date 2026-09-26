import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
private final class StubLayaDiscoveryService: BonjourBackendDiscoveryServiceProtocol {
    var state: BonjourBackendDiscoveryService.State
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(state: BonjourBackendDiscoveryService.State) {
        self.state = state
    }

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }
}

private actor RecordingLayaClassifierClient: LayaClassifierClientProtocol {
    struct Call: Sendable {
        let host: String
        let port: Int
        let model: String
        let stateData: Data
        let questions: [String: LayaQuestion]
        let timeoutSeconds: TimeInterval
    }

    private let response: LayaClassifierResponse
    private var call: Call?

    init(response: LayaClassifierResponse) {
        self.response = response
    }

    func classify<State: Encodable & Sendable>(
        host: String,
        port: Int,
        model: String,
        state: State,
        questions: [String: LayaQuestion],
        timeoutSeconds: TimeInterval
    ) async throws -> LayaClassifierResponse {
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

    func recordedCall() -> Call? {
        call
    }
}

@Test @MainActor
func layaCompanionBackendSendsStructuredStateAndMapsDirectAction() async throws {
    let model = "aac6fef/laya-multilingual-mlx"
    let discovery = StubLayaDiscoveryService(
        state: .resolved(
            host: "mac.local",
            port: 8767,
            txtRecord: [
                "engine": "laya-mlx",
                "engine_impl": model,
            ]
        )
    )
    let client = RecordingLayaClassifierClient(
        response: layaChoiceResponse(model: model, choice: "respond", confidence: 0.73)
    )
    let backend = LayaNetworkCompanionDecisionBackend(
        discoveryService: discovery,
        client: client,
        requestTimeoutSeconds: 0.8
    )

    let decision = try await backend.decide(
        CompanionDecisionInput(
            nowTimestampSeconds: 100,
            heldNotesCount: 0,
            sustainValue: 0,
            recentIOIMedianSeconds: 0.42,
            recentVelocityTrend: -1.5,
            recentNoteDensityPerSecond: 0,
            lastUserEventTimestampSeconds: 98.8,
            lastNoteOnTimestampSeconds: 98.5,
            activePitchCenter: nil,
            isAIPlaybackActive: false,
            recentNotes: [
                CompanionDecisionNote(
                    midi: 64,
                    velocity: 81,
                    onsetSecondsAgo: 1.5,
                    durationSeconds: 0.7
                ),
            ]
        )
    )

    #expect(decision == CompanionDecision(action: .respond, confidence: 0.73))
    let call = try #require(await client.recordedCall())
    #expect(call.host == "mac.local")
    #expect(call.port == 8767)
    #expect(call.model == model)
    #expect(call.timeoutSeconds == 0.8)

    let state = try #require(
        JSONSerialization.jsonObject(with: call.stateData) as? [String: Any]
    )
    #expect(state["held_notes_count"] as? Int == 0)
    #expect(state["sustain_value"] as? Int == 0)
    #expect(state["recent_ioi_median_seconds"] as? Double == 0.42)
    #expect(state["recent_velocity_trend"] as? Double == -1.5)
    #expect(state["recent_note_density_per_second"] as? Double == 0)
    let secondsSinceLastUserEvent = try #require(
        state["seconds_since_last_user_event"] as? Double
    )
    #expect(abs(secondsSinceLastUserEvent - 1.2) < 1e-9)
    #expect(state["seconds_since_last_note_on"] as? Double == 1.5)
    #expect(state["active_pitch_center"] is NSNull)
    #expect(state["is_ai_playback_active"] as? Bool == false)
    let notes = try #require(state["recent_notes"] as? [[String: Any]])
    #expect(notes.count == 1)
    #expect(notes[0]["midi"] as? Int == 64)
    #expect(notes[0]["velocity"] as? Int == 81)
    #expect(notes[0]["onset_seconds_ago"] as? Double == 1.5)
    #expect(notes[0]["duration_seconds"] as? Double == 0.7)

    guard case let .choice(instructions, criteria) = try #require(call.questions["action"]) else {
        Issue.record("Expected one Laya choice question.")
        return
    }
    #expect(instructions.contains("observable MIDI state"))
    #expect(criteria["listen"] == "The user is actively playing, holding notes, sustaining, or only taking a brief musical breath. The AI should stay silent and keep listening.")
    #expect(criteria["respond"] == "The user's phrase has clearly ended: no held notes, sustain is released, and a clear gap has formed. The AI should answer the completed phrase.")
}

@Test @MainActor
func layaCompanionBackendRejectsUnknownActionWithoutFallback() async throws {
    let model = "aac6fef/laya-multilingual-mlx"
    let discovery = StubLayaDiscoveryService(
        state: .resolved(
            host: "mac.local",
            port: 8767,
            txtRecord: ["engine_impl": model]
        )
    )
    let client = RecordingLayaClassifierClient(
        response: layaChoiceResponse(model: model, choice: "dance", confidence: 0.91)
    )
    let backend = LayaNetworkCompanionDecisionBackend(
        discoveryService: discovery,
        client: client
    )

    await #expect(throws: LayaNetworkCompanionDecisionBackendError.invalidAction("dance")) {
        _ = try await backend.decide(layaTestInput())
    }
}

@Test @MainActor
func layaCompanionBackendReportsDiscoveryDenialWithoutRuleFallback() async throws {
    let discovery = StubLayaDiscoveryService(state: .denied)
    let client = RecordingLayaClassifierClient(
        response: layaChoiceResponse(
            model: "aac6fef/laya-multilingual-mlx",
            choice: "listen",
            confidence: 0.8
        )
    )
    let backend = LayaNetworkCompanionDecisionBackend(
        discoveryService: discovery,
        client: client
    )

    await #expect(throws: LayaNetworkCompanionDecisionBackendError.discoveryDenied) {
        _ = try await backend.decide(layaTestInput())
    }
    #expect(await client.recordedCall() == nil)
}

private func layaChoiceResponse(
    model: String,
    choice: String,
    confidence: Double
) -> LayaClassifierResponse {
    LayaClassifierResponse(
        model: model,
        answers: [
            "action": .choice(
                LayaChoiceAnswer(
                    choice: choice,
                    confidence: confidence,
                    action: LayaActionTrace(actProbability: 0.6),
                    probabilities: [choice: 1]
                )
            ),
        ],
        usage: LayaClassifierUsage(inputTokens: 42, outputTokens: 0),
        latencyMS: 11
    )
}

private func layaTestInput() -> CompanionDecisionInput {
    CompanionDecisionInput(
        nowTimestampSeconds: 10,
        heldNotesCount: 1,
        sustainValue: 0,
        recentIOIMedianSeconds: 0.25,
        recentVelocityTrend: 0,
        recentNoteDensityPerSecond: 4,
        lastUserEventTimestampSeconds: 9.9,
        lastNoteOnTimestampSeconds: 9.9,
        activePitchCenter: 62,
        isAIPlaybackActive: false
    )
}
