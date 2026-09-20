import Foundation

enum QwenNetworkCompanionDecisionBackendError: Error, Equatable {
    case backendNotResolved
    case discoveryDenied
    case discoveryFailed(message: String)
}

actor QwenNetworkCompanionDecisionBackend: CompanionDecisionBackendProtocol {
    nonisolated let kind: CompanionDecisionBackendKind = .networkBonjourQwen35
    nonisolated let displayName = "Qwen3.5-0.8B（电脑本地，实验）"

    private let discoveryService: any BonjourBackendDiscoveryServiceProtocol
    private let client: any CompanionDecisionClientProtocol
    private let discoveryTimeout: Duration
    private let requestTimeoutSeconds: TimeInterval

    init(
        discoveryService: any BonjourBackendDiscoveryServiceProtocol,
        client: any CompanionDecisionClientProtocol = CompanionDecisionClient(),
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
        let response = try await client.decide(
            host: endpoint.host,
            port: endpoint.port,
            input: input,
            timeoutSeconds: requestTimeoutSeconds
        )
        return CompanionDecision(
            action: response.action,
            confidence: response.confidence
        )
    }

    private func waitForResolvedEndpoint() async throws -> (host: String, port: Int) {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: discoveryTimeout)

        while clock.now < deadline, Task.isCancelled == false {
            let state = await MainActor.run { discoveryService.state }
            switch state {
            case let .resolved(host, port, _):
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
