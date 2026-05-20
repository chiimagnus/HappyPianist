import Foundation
import ImprovProtocol

enum NetworkBonjourHTTPImprovBackendError: Error, LocalizedError, Equatable {
    case backendNotResolved
    case discoveryDenied
    case discoveryFailed(message: String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .backendNotResolved:
            "Network backend not resolved."
        case .discoveryDenied:
            "Local network discovery permission denied."
        case let .discoveryFailed(message):
            "Local network discovery failed: \(message)"
        case .emptyReply:
            "Backend returned an empty reply."
        }
    }
}

actor NetworkBonjourHTTPImprovBackend: ImprovBackendProtocol {
    nonisolated let kind: ImprovBackendKind = .networkBonjourHTTP
    nonisolated let displayName: String = "网络本地连接"

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

    func generatePlaybackPlan(
        request: ImprovGenerateRequest,
        timeout: Duration
    ) async throws -> ImprovBackendPlaybackPlan {
        await MainActor.run {
            if case .idle = discoveryService.state {
                discoveryService.start()
            }
        }

        let resolved = try await waitForResolvedEndpoint(timeout: timeout)
        let timeoutSeconds = durationToTimeInterval(timeout)

        let response = try await backendClient.generate(
            host: resolved.host,
            port: resolved.port,
            request: request,
            timeoutSeconds: timeoutSeconds
        )

        let schedule = scheduleBuilder.buildSchedule(from: response.notes)
        guard schedule.isEmpty == false else {
            throw NetworkBonjourHTTPImprovBackendError.emptyReply
        }

        return .schedule(schedule)
    }

    private func waitForResolvedEndpoint(timeout: Duration) async throws -> (host: String, port: Int) {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline, Task.isCancelled == false {
            let state = await MainActor.run { discoveryService.state }

            switch state {
            case let .resolved(host, port):
                return (host, port)
            case .denied:
                throw NetworkBonjourHTTPImprovBackendError.discoveryDenied
            case let .failed(message):
                throw NetworkBonjourHTTPImprovBackendError.discoveryFailed(message: message)
            case .idle, .discovering:
                break
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        throw NetworkBonjourHTTPImprovBackendError.backendNotResolved
    }

    private nonisolated func durationToTimeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
