import Foundation
import ImprovProtocol

enum DuetNetworkBonjourHTTPImprovBackendError: Error, LocalizedError, Equatable {
    case backendNotResolved
    case discoveryDenied
    case discoveryFailed(message: String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .backendNotResolved:
            "Duet network backend not resolved."
        case .discoveryDenied:
            "Local network discovery permission denied."
        case let .discoveryFailed(message):
            "Local network discovery failed: \(message)"
        case .emptyReply:
            "Backend returned an empty reply."
        }
    }
}

actor DuetNetworkBonjourHTTPImprovBackend: ImprovBackendProtocol {
    nonisolated let kind: ImprovBackendKind = .networkBonjourHTTPDuet
    nonisolated let displayName: String = "网络本地连接（A.I. Duet / Magenta）"

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
            throw DuetNetworkBonjourHTTPImprovBackendError.emptyReply
        }

        return .schedule(schedule, backendLatencyMS: response.latencyMS)
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
                throw DuetNetworkBonjourHTTPImprovBackendError.discoveryDenied
            case let .failed(message):
                throw DuetNetworkBonjourHTTPImprovBackendError.discoveryFailed(message: message)
            case .idle, .discovering:
                break
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        throw DuetNetworkBonjourHTTPImprovBackendError.backendNotResolved
    }

    private nonisolated func durationToTimeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
