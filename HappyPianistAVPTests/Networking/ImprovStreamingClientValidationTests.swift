import Foundation
@testable import HappyPianistAVP
import Testing

private actor ScriptedWebSocketTask: WebSocketTaskProtocol {
    private var messages: [Data]

    init(messages: [Data]) {
        self.messages = messages
    }

    nonisolated func resume() {}

    func send(_: URLSessionWebSocketTask.Message) async throws {}

    func receive() async throws -> URLSessionWebSocketTask.Message {
        guard messages.isEmpty == false else {
            throw URLError(.badServerResponse)
        }
        return .data(messages.removeFirst())
    }

    nonisolated func cancel(with _: URLSessionWebSocketTask.CloseCode, reason _: Data?) {}
}

@Test
func streamingClientAcceptsSequentialNonOverlappingChunks() async throws {
    let chunks = [
        ImprovStreamChunkV2(
            seq: 0,
            isFinal: false,
            timeRange: ImprovStreamTimeRange(start: 0, end: 1),
            events: [.note(note: 60, velocity: 90, time: 0.2, duration: 0.3)]
        ),
        ImprovStreamChunkV2(
            seq: 1,
            isFinal: true,
            timeRange: ImprovStreamTimeRange(start: 1, end: 1),
            events: []
        ),
    ]

    let received = try await collectChunks(from: chunks)

    #expect(received == chunks)
}

@Test
func streamingClientRejectsUnexpectedSequence() async throws {
    let chunks = [
        ImprovStreamChunkV2(
            seq: 0,
            isFinal: false,
            timeRange: ImprovStreamTimeRange(start: 0, end: 1),
            events: []
        ),
        ImprovStreamChunkV2(
            seq: 2,
            isFinal: true,
            timeRange: ImprovStreamTimeRange(start: 1, end: 1),
            events: []
        ),
    ]

    let error = await streamError(from: chunks)

    #expect(error as? ImprovStreamingClientError == .unexpectedSequence(expected: 1, actual: 2))
}

@Test
func streamingClientRejectsOverlappingTimeRanges() async throws {
    let chunks = [
        ImprovStreamChunkV2(
            seq: 0,
            isFinal: false,
            timeRange: ImprovStreamTimeRange(start: 0, end: 1),
            events: []
        ),
        ImprovStreamChunkV2(
            seq: 1,
            isFinal: true,
            timeRange: ImprovStreamTimeRange(start: 0.5, end: 1.5),
            events: []
        ),
    ]

    let error = await streamError(from: chunks)

    #expect(
        error as? ImprovStreamingClientError
            == .overlappingTimeRange(previousEnd: 1, nextStart: 0.5)
    )
}

@Test
func streamingClientRejectsEventOutsideChunkTimeRange() async throws {
    let chunks = [
        ImprovStreamChunkV2(
            seq: 0,
            isFinal: true,
            timeRange: ImprovStreamTimeRange(start: 1, end: 2),
            events: [.note(note: 60, velocity: 90, time: 0.5, duration: 0.3)]
        )
    ]

    let error = await streamError(from: chunks)

    #expect(
        error as? ImprovStreamingClientError
            == .eventOutsideTimeRange(sequence: 0, eventTime: 0.5, start: 1, end: 2)
    )
}

@Test(arguments: [
    """
    {"start": -1.0, "end": 1.0}
    """,
    """
    {"start": 2.0, "end": 1.0}
    """,
])
func streamingTimeRangeRejectsInvalidValues(json: String) {
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ImprovStreamTimeRange.self, from: Data(json.utf8))
    }
}

private func collectChunks(from chunks: [ImprovStreamChunkV2]) async throws -> [ImprovStreamChunkV2] {
    let task = ScriptedWebSocketTask(messages: try chunks.map { try JSONEncoder().encode($0) })
    let client = ImprovStreamingClient(
        urlSession: .shared,
        makeWebSocketTask: { _, _ in task }
    )
    let request = ImprovGenerateRequestV2(
        events: [],
        params: ImprovGenerateParams(topP: 0.9, maxTokens: 1, strategy: "test"),
        sessionID: "validation"
    )
    let stream = try await client.streamChunks(
        url: try #require(URL(string: "ws://example.com/stream")),
        start: ImprovStreamStartRequestV2(request: request),
        timeout: .seconds(1)
    )

    var received: [ImprovStreamChunkV2] = []
    for try await chunk in stream {
        received.append(chunk)
    }
    return received
}

private func streamError(from chunks: [ImprovStreamChunkV2]) async -> Error? {
    do {
        _ = try await collectChunks(from: chunks)
        return nil
    } catch {
        return error
    }
}
