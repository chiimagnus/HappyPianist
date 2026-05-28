import Foundation
import ImprovProtocol

protocol WebSocketTaskProtocol: AnyObject, Sendable {
    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSessionWebSocketTask: WebSocketTaskProtocol {}

enum ImprovStreamingClientError: Error, LocalizedError, Equatable {
    case invalidMessage
    case timeout
    case serverError(message: String)
    case protocolVersionMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidMessage:
            "Invalid WebSocket message."
        case .timeout:
            "WebSocket stream timed out."
        case let .serverError(message):
            "WebSocket server error: \(message)"
        case let .protocolVersionMismatch(expected, actual):
            "WebSocket protocol version mismatch (expected \(expected), got \(actual))."
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

        let encoder = JSONEncoder()
        let startData = try encoder.encode(start)
        guard let startText = String(data: startData, encoding: .utf8) else {
            throw ImprovStreamingClientError.invalidMessage
        }

        return AsyncThrowingStream { continuation in
            var request = URLRequest(url: url)
            request.timeoutInterval = timeoutInterval

            let wsTask = makeWebSocketTask(request)
            wsTask.resume()

            let decoder = JSONDecoder()

            let sendTask = Task {
                do {
                    try await wsTask.send(.string(startText))
                } catch {
                    wsTask.cancel(with: .goingAway, reason: nil)
                    continuation.finish(throwing: error)
                }
            }

            let receiveTask = Task {
                do {
                    while Task.isCancelled == false {
                        let message = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
                            group.addTask { try await wsTask.receive() }
                            group.addTask {
                                try await Task.sleep(for: timeout)
                                throw ImprovStreamingClientError.timeout
                            }
                            let next = try await group.next()
                            group.cancelAll()
                            guard let next else {
                                throw CancellationError()
                            }
                            return next
                        }

                        let data: Data
                        switch message {
                        case let .data(messageData):
                            data = messageData
                        case let .string(text):
                            guard let messageData = text.data(using: .utf8) else {
                                throw ImprovStreamingClientError.invalidMessage
                            }
                            data = messageData
                        @unknown default:
                            throw ImprovStreamingClientError.invalidMessage
                        }

                        if let serverError = try? decoder.decode(ImprovErrorResponse.self, from: data),
                           serverError.type == "error"
                        {
                            throw ImprovStreamingClientError.serverError(message: serverError.message)
                        }

                        let chunk = try decoder.decode(ImprovStreamChunkV2.self, from: data)
                        if chunk.protocolVersion != 2 {
                            throw ImprovStreamingClientError.protocolVersionMismatch(expected: 2, actual: chunk.protocolVersion)
                        }
                        if chunk.type != "chunk" {
                            throw ImprovStreamingClientError.invalidMessage
                        }
                        continuation.yield(chunk)

                        if chunk.isFinal {
                            break
                        }
                    }

                    wsTask.cancel(with: .normalClosure, reason: nil)
                    continuation.finish()
                } catch {
                    wsTask.cancel(with: .goingAway, reason: nil)
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                sendTask.cancel()
                receiveTask.cancel()
                wsTask.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private nonisolated func durationToTimeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
