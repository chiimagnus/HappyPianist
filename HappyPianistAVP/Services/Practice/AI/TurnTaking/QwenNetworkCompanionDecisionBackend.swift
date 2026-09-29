import Foundation

enum QwenNetworkCompanionDecisionBackendError: Error, Equatable {
    case backendNotResolved
    case discoveryDenied
    case discoveryFailed(message: String)
    case missingModelIdentity
    case unexpectedModelIdentity(String)
}

actor QwenNetworkCompanionDecisionBackend: CompanionDecisionBackendProtocol {
    nonisolated let kind: CompanionDecisionBackendKind = .networkBonjourQwen
    nonisolated let displayName = "Qwen3.5-0.8B（电脑本地，实验）"

    private let discoveryService: any BonjourBackendDiscoveryServiceProtocol
    private let client: any QwenCompanionDecisionClientProtocol
    private let discoveryTimeout: Duration
    private let requestTimeoutSeconds: TimeInterval

    init(
        discoveryService: any BonjourBackendDiscoveryServiceProtocol,
        client: any QwenCompanionDecisionClientProtocol = QwenCompanionDecisionClient(),
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
        let response = try await client.decide(
            host: endpoint.host,
            port: endpoint.port,
            state: makeState(input),
            timeoutSeconds: requestTimeoutSeconds
        )
        return CompanionDecision(action: domainAction(response.action))
    }

    private func makeState(_ input: CompanionDecisionInput) -> QwenCompanionState {
        let secondsSinceLastNoteOn = input.lastNoteOnTimestampSeconds.map {
            max(0, input.nowTimestampSeconds - $0)
        }
        return QwenCompanionState(
            heldNotesCount: input.heldNotesCount,
            sustainValue: input.sustainValue,
            recentIOIMedianSeconds: input.recentIOIMedianSeconds,
            recentNoteDensityPerSecond: input.recentNoteDensityPerSecond,
            secondsSinceLastNoteOn: secondsSinceLastNoteOn,
            isAIPlaybackActive: input.isAIPlaybackActive,
            userNoteOnSinceAIPlaybackStarted: input.userNoteOnSinceAIPlaybackStarted
        )
    }

    private func domainAction(_ action: QwenCompanionAction) -> CompanionAction {
        switch action {
        case .listen:
            .listen
        case .support:
            .support
        case .sparse:
            .sparse
        case .yield:
            .yield
        case .respond:
            .respond
        }
    }

    private func waitForResolvedEndpoint() async throws -> (host: String, port: Int) {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: discoveryTimeout)

        while clock.now < deadline, Task.isCancelled == false {
            let state = await MainActor.run { discoveryService.state }
            switch state {
            case let .resolved(host, port, txtRecord):
                guard let model = txtRecord["engine_impl"], model.isEmpty == false else {
                    throw QwenNetworkCompanionDecisionBackendError.missingModelIdentity
                }
                guard model == QwenCompanionDecisionClient.expectedModel else {
                    throw QwenNetworkCompanionDecisionBackendError.unexpectedModelIdentity(model)
                }
                return (host, port)
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
