import Foundation
import ImprovProtocol

enum ImprovStreamingClientError: Error, LocalizedError, Equatable {
    case invalidMessage

    var errorDescription: String? {
        switch self {
        case .invalidMessage:
            "Invalid WebSocket message."
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

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
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

            let wsTask = urlSession.webSocketTask(with: request)
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
                        let message = try await wsTask.receive()
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

                        let chunk = try decoder.decode(ImprovStreamChunkV2.self, from: data)
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
