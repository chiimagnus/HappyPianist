import Foundation

enum AriaNetworkBonjourWebSocketImprovBackendError: Error, LocalizedError, Equatable {
    case backendNotResolved
    case discoveryDenied
    case discoveryFailed(message: String)
    case missingWebSocketPath
    case invalidWebSocketURL
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .backendNotResolved:
            "Aria network backend not resolved."
        case .discoveryDenied:
            "Local network discovery permission denied."
        case let .discoveryFailed(message):
            "Local network discovery failed: \(message)"
        case .missingWebSocketPath:
            "Backend does not advertise ws_path."
        case .invalidWebSocketURL:
            "Invalid WebSocket URL."
        case .emptyReply:
            "Backend returned an empty reply."
        }
    }
}

actor AriaNetworkBonjourWebSocketImprovBackend: ImprovBackendProtocol, ImprovStreamingBackendProtocol {
    nonisolated let kind: ImprovBackendKind = .networkBonjourWebSocketAriaV2
    nonisolated let displayName: String = "网络本地连接（Aria v2 Streaming）"

    private let discoveryService: any BonjourBackendDiscoveryServiceProtocol
    private let streamingClient: any ImprovStreamingClientProtocol
    private let scheduleBuilder: ImprovScheduleBuilder

    init(
        discoveryService: any BonjourBackendDiscoveryServiceProtocol,
        streamingClient: any ImprovStreamingClientProtocol = ImprovStreamingClient(),
        scheduleBuilder: ImprovScheduleBuilder = ImprovScheduleBuilder()
    ) {
        self.discoveryService = discoveryService
        self.streamingClient = streamingClient
        self.scheduleBuilder = scheduleBuilder
    }

    func streamChunks(
        request: ImprovGenerateRequestV2,
        timeout: Duration
    ) async throws -> AsyncThrowingStream<ImprovStreamChunkV2, Error> {
        await MainActor.run {
            if case .idle = discoveryService.state {
                discoveryService.start()
            }
        }

        let resolved = try await waitForResolvedEndpoint(timeout: timeout)
        guard let rawWSPath = resolved.txtRecord["ws_path"], rawWSPath.isEmpty == false else {
            throw AriaNetworkBonjourWebSocketImprovBackendError.missingWebSocketPath
        }

        var components = URLComponents()
        components.scheme = "ws"
        components.host = resolved.host
        components.port = resolved.port
        components.path = rawWSPath.hasPrefix("/") ? rawWSPath : "/\(rawWSPath)"

        guard let url = components.url else {
            throw AriaNetworkBonjourWebSocketImprovBackendError.invalidWebSocketURL
        }

        let start = ImprovStreamStartRequestV2(request: request)
        return try await streamingClient.streamChunks(url: url, start: start, timeout: timeout)
    }

    func generatePlaybackPlan(
        request: ImprovGenerateRequestV2,
        timeout: Duration
    ) async throws -> ImprovBackendPlaybackPlan {
        var events: [ImprovEvent] = []
        let stream = try await streamChunks(request: request, timeout: timeout)
        for try await chunk in stream {
            events.append(contentsOf: chunk.events)
        }

        let schedule = scheduleBuilder.buildSchedule(from: events)
        guard schedule.isEmpty == false else {
            throw AriaNetworkBonjourWebSocketImprovBackendError.emptyReply
        }

        return .schedule(schedule, backendLatencyMS: nil)
    }

    private func waitForResolvedEndpoint(timeout: Duration) async throws -> (host: String, port: Int, txtRecord: [String: String]) {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline, Task.isCancelled == false {
            let state = await MainActor.run { discoveryService.state }

            switch state {
            case let .resolved(host, port, txtRecord):
                return (host, port, txtRecord)
            case .denied:
                throw AriaNetworkBonjourWebSocketImprovBackendError.discoveryDenied
            case let .failed(message):
                throw AriaNetworkBonjourWebSocketImprovBackendError.discoveryFailed(message: message)
            case .idle, .discovering:
                break
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        throw AriaNetworkBonjourWebSocketImprovBackendError.backendNotResolved
    }
}
