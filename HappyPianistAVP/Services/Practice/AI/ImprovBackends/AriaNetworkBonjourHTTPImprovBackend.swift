import Foundation

enum AriaNetworkBonjourHTTPImprovBackendError: Error, LocalizedError, Equatable {
    case backendNotResolved
    case discoveryDenied
    case discoveryFailed(message: String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .backendNotResolved:
            "Aria network backend not resolved."
        case .discoveryDenied:
            "Local network discovery permission denied."
        case let .discoveryFailed(message):
            "Local network discovery failed: \(message)"
        case .emptyReply:
            "Backend returned an empty reply."
        }
    }
}

actor AriaNetworkBonjourHTTPImprovBackend: ImprovBackendProtocol {
    nonisolated let kind: ImprovBackendKind = .networkBonjourHTTPAriaV2
    nonisolated let displayName: String = "网络本地连接（Aria v2）"

    private let discoveryService: any BonjourBackendDiscoveryServiceProtocol
    private let backendClient: any ImprovBackendClientProtocol
    private let scheduleBuilder: ImprovScheduleBuilder

    init(
        discoveryService: any BonjourBackendDiscoveryServiceProtocol,
        backendClient: any ImprovBackendClientProtocol = ImprovBackendClient(),
        scheduleBuilder: ImprovScheduleBuilder = ImprovScheduleBuilder()
    ) {
        self.discoveryService = discoveryService
        self.backendClient = backendClient
        self.scheduleBuilder = scheduleBuilder
    }

    func generateCreativeResponse(
        phrase: CreativeDuetPhrase,
        generation: CreativeDuetGeneration,
        timeout: Duration
    ) async throws -> CreativeDuetResponse {
        await MainActor.run {
            switch discoveryService.state {
            case .idle, .failed:
                discoveryService.start()
            case .discovering, .resolved, .denied:
                break
            }
        }

        let resolved = try await waitForResolvedEndpoint(timeout: timeout)
        let timeoutSeconds = durationToTimeInterval(timeout)
        let request = ImprovGenerateRequestV2(
            events: phrase.events,
            params: generation.parameters,
            sessionID: generation.sessionID
        )

        let response = try await backendClient.generateV2(
            host: resolved.host,
            port: resolved.port,
            request: request,
            timeoutSeconds: timeoutSeconds
        )

        let schedule = scheduleBuilder.buildSchedule(from: response.events)
        guard schedule.isEmpty == false else {
            throw AriaNetworkBonjourHTTPImprovBackendError.emptyReply
        }

        return CreativeDuetResponse(
            schedule: schedule,
            provider: kind,
            generation: generation,
            provenance: .backendGenerated(latencyMS: response.latencyMS)
        )
    }

    private func waitForResolvedEndpoint(timeout: Duration) async throws -> (host: String, port: Int) {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline, Task.isCancelled == false {
            let state = await MainActor.run { discoveryService.state }

            switch state {
            case let .resolved(host, port, _):
                return (host, port)
            case .denied:
                throw AriaNetworkBonjourHTTPImprovBackendError.discoveryDenied
            case let .failed(message):
                throw AriaNetworkBonjourHTTPImprovBackendError.discoveryFailed(message: message)
            case .idle, .discovering:
                break
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        throw AriaNetworkBonjourHTTPImprovBackendError.backendNotResolved
    }

    private nonisolated func durationToTimeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
