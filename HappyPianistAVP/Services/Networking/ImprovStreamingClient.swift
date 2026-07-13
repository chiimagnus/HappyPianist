import Foundation

protocol WebSocketTaskProtocol: AnyObject, Sendable {
    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSessionWebSocketTask: WebSocketTaskProtocol {}

enum ImprovStreamingClientError: Error, LocalizedError, Equatable {
    case invalidMessage
    case invalidTimeout
    case timeout
    case serverError(message: String)
    case protocolVersionMismatch(expected: Int, actual: Int)
    case unexpectedSequence(expected: Int, actual: Int)
    case overlappingTimeRange(previousEnd: Double, nextStart: Double)
    case eventOutsideTimeRange(sequence: Int, eventTime: Double, start: Double, end: Double)

    var errorDescription: String? {
        switch self {
        case .invalidMessage:
            "Invalid WebSocket message."
        case .invalidTimeout:
            "WebSocket timeout must be greater than zero."
        case .timeout:
            "WebSocket stream timed out."
        case let .serverError(message):
            "WebSocket server error: \(message)"
        case let .protocolVersionMismatch(expected, actual):
            "WebSocket protocol version mismatch (expected \(expected), got \(actual))."
        case let .unexpectedSequence(expected, actual):
            "WebSocket chunk sequence mismatch (expected \(expected), got \(actual))."
        case let .overlappingTimeRange(previousEnd, nextStart):
            "WebSocket chunk time range overlaps the preceding chunk (\(nextStart) < \(previousEnd))."
        case let .eventOutsideTimeRange(sequence, eventTime, start, end):
            "WebSocket chunk \(sequence) contains an event at \(eventTime) outside \(start)...\(end)."
        }
    }
}

protocol ImprovStreamingClientProtocol: Sendable {
    func streamChunks(
        url: URL,
        start: ImprovStreamStartRequestV2,
        timeout: Duration
    ) async throws -> AsyncThrowingStream<ImprovStreamChunkV2, Error>
}

actor ImprovStreamingClient: ImprovStreamingClientProtocol {
    private struct ValidationState {
        var nextSequence: Int = 0
        var previousTimeRangeEnd: Double = 0
    }

    private let urlSession: URLSession
    private let makeWebSocketTask: @Sendable (URLRequest) -> any WebSocketTaskProtocol

    init(
        urlSession: URLSession = .shared,
        makeWebSocketTask: (@Sendable (URLRequest, URLSession) -> any WebSocketTaskProtocol)? = nil
    ) {
        self.urlSession = urlSession
        if let makeWebSocketTask {
            self.makeWebSocketTask = { request in
                makeWebSocketTask(request, urlSession)
            }
        } else {
            self.makeWebSocketTask = { request in
                urlSession.webSocketTask(with: request)
            }
        }
    }

    func streamChunks(
        url: URL,
        start: ImprovStreamStartRequestV2,
        timeout: Duration
    ) async throws -> AsyncThrowingStream<ImprovStreamChunkV2, Error> {
        let timeoutInterval = durationToTimeInterval(timeout)
        guard timeoutInterval.isFinite, timeoutInterval > 0 else {
            throw ImprovStreamingClientError.invalidTimeout
        }

        let encoder = JSONEncoder()
        let startData = try encoder.encode(start)
        guard let startText = String(data: startData, encoding: .utf8) else {
            throw ImprovStreamingClientError.invalidMessage
        }

        return AsyncThrowingStream { continuation in
            var request = URLRequest(url: url)
            request.timeoutInterval = timeoutInterval

            let webSocketTask = makeWebSocketTask(request)
            webSocketTask.resume()

            let workerTask = Task {
                do {
                    try await webSocketTask.send(.string(startText))

                    let decoder = JSONDecoder()
                    var validationState = ValidationState()

                    while Task.isCancelled == false {
                        let message = try await receive(from: webSocketTask, timeout: timeout)
                        let data = try messageData(from: message)

                        if let serverError = try? decoder.decode(ImprovErrorResponse.self, from: data),
                           serverError.type == "error"
                        {
                            throw ImprovStreamingClientError.serverError(message: serverError.message)
                        }

                        let chunk = try decoder.decode(ImprovStreamChunkV2.self, from: data)
                        try validate(chunk, state: &validationState)
                        continuation.yield(chunk)

                        if chunk.isFinal {
                            break
                        }
                    }

                    webSocketTask.cancel(with: .normalClosure, reason: nil)
                    continuation.finish()
                } catch {
                    webSocketTask.cancel(with: .goingAway, reason: nil)
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                workerTask.cancel()
                webSocketTask.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private nonisolated func receive(
        from webSocketTask: any WebSocketTaskProtocol,
        timeout: Duration
    ) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask {
                try await webSocketTask.receive()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ImprovStreamingClientError.timeout
            }

            guard let message = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return message
        }
    }

    private nonisolated func messageData(
        from message: URLSessionWebSocketTask.Message
    ) throws -> Data {
        switch message {
        case let .data(data):
            return data
        case let .string(text):
            guard let data = text.data(using: .utf8) else {
                throw ImprovStreamingClientError.invalidMessage
            }
            return data
        @unknown default:
            throw ImprovStreamingClientError.invalidMessage
        }
    }

    private nonisolated func validate(
        _ chunk: ImprovStreamChunkV2,
        state: inout ValidationState
    ) throws {
        guard chunk.protocolVersion == 2 else {
            throw ImprovStreamingClientError.protocolVersionMismatch(
                expected: 2,
                actual: chunk.protocolVersion
            )
        }
        guard chunk.type == "chunk" else {
            throw ImprovStreamingClientError.invalidMessage
        }
        guard chunk.seq == state.nextSequence else {
            throw ImprovStreamingClientError.unexpectedSequence(
                expected: state.nextSequence,
                actual: chunk.seq
            )
        }

        let tolerance = 1e-9
        guard chunk.timeRange.start + tolerance >= state.previousTimeRangeEnd else {
            throw ImprovStreamingClientError.overlappingTimeRange(
                previousEnd: state.previousTimeRangeEnd,
                nextStart: chunk.timeRange.start
            )
        }

        for event in chunk.events {
            guard event.time + tolerance >= chunk.timeRange.start,
                  event.time <= chunk.timeRange.end + tolerance
            else {
                throw ImprovStreamingClientError.eventOutsideTimeRange(
                    sequence: chunk.seq,
                    eventTime: event.time,
                    start: chunk.timeRange.start,
                    end: chunk.timeRange.end
                )
            }
        }

        state.nextSequence += 1
        state.previousTimeRangeEnd = chunk.timeRange.end
    }

    private nonisolated func durationToTimeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
