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

private actor RecordingQwenCompanionClient: QwenCompanionDecisionClientProtocol {
    struct Call: Sendable {
        let host: String
        let port: Int
        let state: QwenCompanionState
        let timeoutSeconds: TimeInterval
    }

    private let response: QwenCompanionDecisionResponse
    private var call: Call?

    init(response: QwenCompanionDecisionResponse) {
        self.response = response
    }

    func decide(
        host: String,
        port: Int,
        state: QwenCompanionState,
        timeoutSeconds: TimeInterval
    ) async throws -> QwenCompanionDecisionResponse {
        call = Call(host: host, port: port, state: state, timeoutSeconds: timeoutSeconds)
        return response
    }

    func recordedCall() -> Call? { call }
}

@Test @MainActor
func qwenCompanionBackendUsesOnlyRemainingDecisionDeadline() async throws {
    let discovery = StubQwenDiscoveryService(
        state: .resolved(
            host: "windows.local",
            port: 8767,
            txtRecord: ["engine_impl": QwenCompanionDecisionClient.expectedModel]
        )
    )
    let client = RecordingQwenCompanionClient(response: qwenDecisionResponse(action: .respond))
    let backend = QwenNetworkCompanionDecisionBackend(discoveryService: discovery, client: client)
    let deadline = ContinuousClock().now.advanced(by: .milliseconds(100))

    let decision = try await backend.decide(
        qwenTestInput(density: 0, aiPlaybackActive: false, postStartNoteOn: false),
        deadline: deadline
    )

    #expect(decision == CompanionDecision(action: .respond))
    let call = try #require(await client.recordedCall())
    #expect(call.host == "windows.local")
    #expect(call.port == 8767)
    #expect(call.timeoutSeconds > 0)
    #expect(call.timeoutSeconds <= 0.1)
    #expect(call.state.heldNotesCount == 0)
    #expect(call.state.secondsSinceLastNoteOn == 1.5)
    #expect(call.state.isAIPlaybackActive == false)
    #expect(call.state.userNoteOnSinceAIPlaybackStarted == false)
}

@Test @MainActor
func qwenCompanionBackendMapsAllTypedServiceActions() async throws {
    let discovery = StubQwenDiscoveryService(
        state: .resolved(
            host: "windows.local",
            port: 8767,
            txtRecord: ["engine_impl": QwenCompanionDecisionClient.expectedModel]
        )
    )

    for action in QwenCompanionAction.allTestCases {
        let backend = QwenNetworkCompanionDecisionBackend(
            discoveryService: discovery,
            client: RecordingQwenCompanionClient(response: qwenDecisionResponse(action: action))
        )
        let decision = try await backend.decide(
            qwenTestInput(density: 3, aiPlaybackActive: true, postStartNoteOn: true),
            deadline: ContinuousClock().now.advanced(by: .seconds(1))
        )
        #expect(decision.action.rawValue == action.rawValue)
    }
}

@Test @MainActor
func qwenCompanionBackendRejectsUnexpectedBonjourModelWithoutCallingClient() async throws {
    let discovery = StubQwenDiscoveryService(
        state: .resolved(host: "windows.local", port: 8767, txtRecord: ["engine_impl": "other-model"])
    )
    let client = RecordingQwenCompanionClient(response: qwenDecisionResponse(action: .listen))
    let backend = QwenNetworkCompanionDecisionBackend(discoveryService: discovery, client: client)

    await #expect(throws: QwenNetworkCompanionDecisionBackendError.unexpectedModelIdentity("other-model")) {
        _ = try await backend.decide(
            qwenTestInput(density: 4, aiPlaybackActive: false, postStartNoteOn: false),
            deadline: ContinuousClock().now.advanced(by: .milliseconds(100))
        )
    }
    #expect(await client.recordedCall() == nil)
}

@Test @MainActor
func qwenCompanionBackendReportsDiscoveryDenialWithoutRuleFallback() async throws {
    let discovery = StubQwenDiscoveryService(state: .denied)
    let client = RecordingQwenCompanionClient(response: qwenDecisionResponse(action: .listen))
    let backend = QwenNetworkCompanionDecisionBackend(discoveryService: discovery, client: client)

    await #expect(throws: QwenNetworkCompanionDecisionBackendError.discoveryDenied) {
        _ = try await backend.decide(
            qwenTestInput(density: 4, aiPlaybackActive: false, postStartNoteOn: false),
            deadline: ContinuousClock().now.advanced(by: .milliseconds(100))
        )
    }
    #expect(await client.recordedCall() == nil)
}

@Test @MainActor
func qwenCompanionBackendStartsIdleOrFailedDiscoveryAndFailsFast() async throws {
    for state in [
        BonjourBackendDiscoveryService.State.idle,
        .failed(message: "old failure"),
    ] {
        let discovery = StubQwenDiscoveryService(state: state)
        let client = RecordingQwenCompanionClient(response: qwenDecisionResponse(action: .listen))
        let backend = QwenNetworkCompanionDecisionBackend(discoveryService: discovery, client: client)

        await #expect(throws: QwenNetworkCompanionDecisionBackendError.backendNotResolved) {
            _ = try await backend.decide(
                qwenTestInput(density: 1, aiPlaybackActive: false, postStartNoteOn: false),
                deadline: ContinuousClock().now.advanced(by: .milliseconds(100))
            )
        }
        #expect(discovery.startCount == 1)
        #expect(await client.recordedCall() == nil)
    }
}

@Test @MainActor
func qwenCompanionBackendDoesNotPollWhileDiscoveryIsInProgress() async throws {
    let discovery = StubQwenDiscoveryService(state: .discovering)
    let client = RecordingQwenCompanionClient(response: qwenDecisionResponse(action: .listen))
    let backend = QwenNetworkCompanionDecisionBackend(discoveryService: discovery, client: client)
    let started = ContinuousClock().now

    await #expect(throws: QwenNetworkCompanionDecisionBackendError.backendNotResolved) {
        _ = try await backend.decide(
            qwenTestInput(density: 1, aiPlaybackActive: false, postStartNoteOn: false),
            deadline: ContinuousClock().now.advanced(by: .milliseconds(100))
        )
    }

    #expect(started.duration(to: ContinuousClock().now) < .milliseconds(50))
    #expect(discovery.startCount == 0)
    #expect(await client.recordedCall() == nil)
}

@Test @MainActor
func qwenCompanionBackendRejectsExpiredDeadlineBeforeHTTP() async throws {
    let discovery = StubQwenDiscoveryService(
        state: .resolved(
            host: "windows.local",
            port: 8767,
            txtRecord: ["engine_impl": QwenCompanionDecisionClient.expectedModel]
        )
    )
    let client = RecordingQwenCompanionClient(response: qwenDecisionResponse(action: .listen))
    let backend = QwenNetworkCompanionDecisionBackend(discoveryService: discovery, client: client)

    do {
        _ = try await backend.decide(
            qwenTestInput(density: 1, aiPlaybackActive: false, postStartNoteOn: false),
            deadline: ContinuousClock().now.advanced(by: .milliseconds(-1))
        )
        Issue.record("Expected expired deadline to fail")
    } catch let error as URLError {
        #expect(error.code == .timedOut)
    }
    #expect(await client.recordedCall() == nil)
}

private func qwenDecisionResponse(action: QwenCompanionAction) -> QwenCompanionDecisionResponse {
    QwenCompanionDecisionResponse(
        model: QwenCompanionDecisionClient.expectedModel,
        action: action,
        semanticScores: QwenSemanticValues(continuing: 0.8, finished: 0.2, space: 0.7, reasserted: 0.1),
        semanticOrderGaps: QwenSemanticValues(continuing: 0.03, finished: 0.02, space: 0.04, reasserted: 0.01),
        usage: QwenCompanionUsage(inputTokens: 120, outputTokens: 0),
        serverLatencyMS: 80
    )
}

private func qwenTestInput(
    density: Double,
    aiPlaybackActive: Bool,
    postStartNoteOn: Bool
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
        isAIPlaybackActive: aiPlaybackActive,
        userNoteOnSinceAIPlaybackStarted: postStartNoteOn
    )
}

private extension QwenCompanionAction {
    static var allTestCases: [Self] { [.listen, .support, .sparse, .yield, .respond] }
}
