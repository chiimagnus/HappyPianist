import Foundation

enum AriaNetworkBonjourHTTPImprovBackendError: Error, LocalizedError, Equatable {
    case backendNotResolved
    case discoveryDenied
    case discoveryFailed(message: String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .backendNotResolved:
            "Aria network backend not resolved within the product deadline."
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
    nonisolated let kind: ImprovBackendKind = .networkBonjourHTTPAria
    nonisolated let displayName: String = "网络本地连接（Aria）"

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
        generation: CreativeDuetGeneration
    ) async throws -> CreativeDuetResponse {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: .seconds(ImprovQualityRubric.Thresholds.v2.maximumResponseLatencySeconds)
        )

        await MainActor.run {
            switch discoveryService.state {
            case .idle, .failed:
                discoveryService.start()
            case .discovering, .resolved, .denied:
                break
            }
        }

        let resolved = try await waitForResolvedEndpoint(deadline: deadline, clock: clock)
        let remaining = clock.now.duration(to: deadline)
        let timeoutSeconds = durationToTimeInterval(remaining)
        guard timeoutSeconds > 0 else {
            throw URLError(.timedOut)
        }

        let request = AriaGenerateRequest(
            events: phrase.events,
            maxTokens: generation.parameters.maxTokens
        )
        let response = try await backendClient.generate(
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

    private func waitForResolvedEndpoint(
        deadline: ContinuousClock.Instant,
        clock: ContinuousClock
    ) async throws -> (host: String, port: Int) {
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
            try await Task.sleep(for: .milliseconds(25))
        }
        throw AriaNetworkBonjourHTTPImprovBackendError.backendNotResolved
    }

    private nonisolated func durationToTimeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
