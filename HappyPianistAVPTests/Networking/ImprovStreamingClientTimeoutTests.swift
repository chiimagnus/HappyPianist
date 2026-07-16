import Foundation
@testable import HappyPianistAVP
import Testing

private final class HangingWebSocketTask: WebSocketTaskProtocol, @unchecked Sendable {
    func resume() {}

    func send(_: URLSessionWebSocketTask.Message) async throws {}

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await Task.sleep(for: .seconds(60))
        return .string("")
    }

    func cancel(with _: URLSessionWebSocketTask.CloseCode, reason _: Data?) {}
}

@Test
func streamingClientTimesOutWhenNoMessagesArrive() async throws {
    let client = ImprovStreamingClient(
        urlSession: .shared,
        makeWebSocketTask: { _, _ in HangingWebSocketTask() }
    )

    let request = ImprovGenerateRequestV2(
        events: [],
        params: ImprovGenerateParams(topP: 0.9, maxTokens: 1, strategy: "test"),
        sessionID: "test"
    )
    let start = ImprovStreamStartRequestV2(request: request)

    let stream = try await client.streamChunks(
        url: #require(URL(string: "ws://example.com/stream")),
        start: start,
        timeout: .milliseconds(30)
    )

    var thrown: Error?
    do {
        for try await _ in stream {}
    } catch {
        thrown = error
    }

    #expect(thrown as? ImprovStreamingClientError == .timeout)
}
