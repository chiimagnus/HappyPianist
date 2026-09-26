import Foundation
@testable import HappyPianistAVP
import os
import Testing

private final class QwenClassifierStubURLProtocol: URLProtocol {
    struct State {
        var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    }

    private static let lock = OSAllocatedUnfairLock(initialState: State())

    static func setHandler(
        _ handler: @Sendable @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.withLock { $0.requestHandler = handler }
    }

    static func clearHandler() {
        lock.withLock { $0.requestHandler = nil }
    }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.lock.withLock({ $0.requestHandler }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct QwenClientTestState: Encodable, Sendable {
    let heldNotesCount: Int
    let isAIPlaybackActive: Bool

    enum CodingKeys: String, CodingKey {
        case heldNotesCount = "held_notes_count"
        case isAIPlaybackActive = "is_ai_playback_active"
    }
}

@Test
func qwenClassifierClientSendsStructuredStateAndTypedChoice() async throws {
    defer { QwenClassifierStubURLProtocol.clearHandler() }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [QwenClassifierStubURLProtocol.self]
    let client = QwenClassifierClient(urlSession: URLSession(configuration: configuration))

    QwenClassifierStubURLProtocol.setHandler { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/classifier")

        let data = try #require(qwenClassifierHTTPBodyData(from: request))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["model"] as? String == "Qwen/Qwen3.5-0.8B")
        let state = try #require(json["state"] as? [String: Any])
        #expect(state["held_notes_count"] as? Int == 1)
        #expect(state["is_ai_playback_active"] as? Bool == true)
        let questions = try #require(json["questions"] as? [String: Any])
        let question = try #require(questions["continuing__true_a"] as? [String: Any])
        #expect(question["type"] as? String == "choice")
        let criteria = try #require(question["criteria"] as? [String: Any])
        #expect(criteria["A"] as? String == "true condition")
        #expect(criteria["B"] as? String == "false condition")

        return try qwenClassifierHTTPResponse(
            request: request,
            statusCode: 200,
            body: qwenClassifierChoiceResponse(outputTokens: 0, includeConfidence: true)
        )
    }

    let response = try await client.classify(
        host: "example.com",
        port: 8767,
        model: "Qwen/Qwen3.5-0.8B",
        state: QwenClientTestState(heldNotesCount: 1, isAIPlaybackActive: true),
        questions: [
            "continuing__true_a": .choice(
                instructions: "Is the phrase continuing?",
                criteria: ["A": "true condition", "B": "false condition"]
            ),
        ],
        timeoutSeconds: 1.5
    )

    guard case let .choice(answer) = try #require(response.answers["continuing__true_a"]) else {
        Issue.record("Expected a choice answer.")
        return
    }
    #expect(answer.choice == "A")
    #expect(answer.confidence == 0.74)
    #expect(answer.probabilities == ["A": 0.74, "B": 0.26])
    #expect(response.usage.outputTokens == 0)
    #expect(response.latencyMS == 17)
}

@Test
func qwenClassifierClientFailsExplicitlyForHTTPDecodeAndOutputTokens() async throws {
    defer { QwenClassifierStubURLProtocol.clearHandler() }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [QwenClassifierStubURLProtocol.self]
    let client = QwenClassifierClient(urlSession: URLSession(configuration: configuration))

    func classify() async throws -> QwenClassifierResponse {
        try await client.classify(
            host: "example.com",
            port: 8767,
            model: "Qwen/Qwen3.5-0.8B",
            state: ["value": 1],
            questions: [
                "continuing__true_a": .choice(
                    instructions: "Choose.",
                    criteria: ["A": "yes", "B": "no"]
                ),
            ],
            timeoutSeconds: 1.5
        )
    }

    QwenClassifierStubURLProtocol.setHandler { request in
        try qwenClassifierHTTPResponse(
            request: request,
            statusCode: 500,
            body: ["message": "classification_failed"]
        )
    }
    await #expect(throws: QwenClassifierClientError.httpError(statusCode: 500, message: "classification_failed")) {
        _ = try await classify()
    }

    QwenClassifierStubURLProtocol.setHandler { request in
        try qwenClassifierHTTPResponse(
            request: request,
            statusCode: 200,
            body: qwenClassifierChoiceResponse(outputTokens: 0, includeConfidence: false)
        )
    }
    await #expect(throws: QwenClassifierClientError.decodeFailed) {
        _ = try await classify()
    }

    QwenClassifierStubURLProtocol.setHandler { request in
        try qwenClassifierHTTPResponse(
            request: request,
            statusCode: 200,
            body: qwenClassifierChoiceResponse(outputTokens: 1, includeConfidence: true)
        )
    }
    await #expect(throws: QwenClassifierClientError.unexpectedOutputTokens(1)) {
        _ = try await classify()
    }
}

private func qwenClassifierChoiceResponse(
    outputTokens: Int,
    includeConfidence: Bool
) -> [String: Any] {
    var answer: [String: Any] = [
        "type": "choice",
        "choice": "A",
        "probabilities": ["A": 0.74, "B": 0.26],
    ]
    if includeConfidence {
        answer["confidence"] = 0.74
    }
    return [
        "model": "Qwen/Qwen3.5-0.8B",
        "answers": ["continuing__true_a": answer],
        "usage": ["input_tokens": 12, "output_tokens": outputTokens],
        "latency_ms": 17,
    ]
}

private func qwenClassifierHTTPResponse(
    request: URLRequest,
    statusCode: Int,
    body: [String: Any]
) throws -> (HTTPURLResponse, Data) {
    let url = try #require(request.url)
    let response = try #require(
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
    )
    return (response, try JSONSerialization.data(withJSONObject: body))
}

private func qwenClassifierHTTPBodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(buffer, count: count)
    }
    return data
}
