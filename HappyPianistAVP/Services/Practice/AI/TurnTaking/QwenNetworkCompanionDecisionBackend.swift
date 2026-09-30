import Foundation

enum QwenNetworkCompanionDecisionBackendError: Error, Equatable {
    case backendNotResolved
    case discoveryDenied
    case missingModelIdentity
    case unexpectedModelIdentity(String)
}

actor QwenNetworkCompanionDecisionBackend: CompanionDecisionBackendProtocol {
    nonisolated let kind: CompanionDecisionBackendKind = .networkBonjourQwen
    nonisolated let displayName = "Qwen3.5-0.8B（电脑本地，实验）"

    private let discoveryService: any BonjourBackendDiscoveryServiceProtocol
    private let client: any QwenCompanionDecisionClientProtocol

    init(
        discoveryService: any BonjourBackendDiscoveryServiceProtocol,
        client: any QwenCompanionDecisionClientProtocol = QwenCompanionDecisionClient()
    ) {
        self.discoveryService = discoveryService
        self.client = client
    }

    func decide(
        _ input: CompanionDecisionInput,
        deadline: ContinuousClock.Instant
    ) async throws -> CompanionDecision {
        let endpoint = try await resolvedEndpointOrStartDiscovery()
        let timeoutSeconds = try remainingSeconds(until: deadline)
        let response = try await client.decide(
            host: endpoint.host,
            port: endpoint.port,
            state: makeState(input),
            timeoutSeconds: timeoutSeconds
        )
        guard ContinuousClock().now < deadline else {
            throw URLError(.timedOut)
        }
        return CompanionDecision(action: domainAction(response.action))
    }

    private func resolvedEndpointOrStartDiscovery() async throws -> (host: String, port: Int) {
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
        case .idle, .failed:
            await MainActor.run { discoveryService.start() }
            throw QwenNetworkCompanionDecisionBackendError.backendNotResolved
        case .discovering:
            throw QwenNetworkCompanionDecisionBackendError.backendNotResolved
        case .denied:
            throw QwenNetworkCompanionDecisionBackendError.discoveryDenied
        }
    }

    private func remainingSeconds(until deadline: ContinuousClock.Instant) throws -> TimeInterval {
        let remaining = ContinuousClock().now.duration(to: deadline)
        let components = remaining.components
        let seconds = TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        guard seconds.isFinite, seconds > 0 else {
            throw URLError(.timedOut)
        }
        return seconds
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
}
