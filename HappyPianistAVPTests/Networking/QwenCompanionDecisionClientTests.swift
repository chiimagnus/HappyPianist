import Foundation
@testable import HappyPianistAVP
import os
import Testing

private final class QwenCompanionStubURLProtocol: URLProtocol {
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

@Test
func qwenCompanionClientSendsOnlyFixedStateAndDecodesDecision() async throws {
    defer { QwenCompanionStubURLProtocol.clearHandler() }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [QwenCompanionStubURLProtocol.self]
    let client = QwenCompanionDecisionClient(urlSession: URLSession(configuration: configuration))

    QwenCompanionStubURLProtocol.setHandler { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/companion-decision")
        #expect(request.timeoutInterval > 0)
        #expect(request.timeoutInterval <= 0.1)

        let data = try #require(qwenCompanionHTTPBodyData(from: request))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == Set(["state"]))
        let state = try #require(json["state"] as? [String: Any])
        #expect(Set(state.keys) == Set([
            "held_notes_count",
            "sustain_value",
            "recent_ioi_median_seconds",
            "recent_note_density_per_second",
            "seconds_since_last_note_on",
            "is_ai_playback_active",
            "user_note_on_since_ai_playback_started",
        ]))
        #expect(state["held_notes_count"] as? Int == 1)
        #expect(state["is_ai_playback_active"] as? Bool == true)
        #expect(state["user_note_on_since_ai_playback_started"] as? Bool == true)

        return try qwenCompanionHTTPResponse(
            request: request,
            statusCode: 200,
            body: qwenCompanionDecisionBody(outputTokens: 0)
        )
    }

    let response = try await client.decide(
        host: "example.com",
        port: 8767,
        state: qwenClientState(),
        timeoutSeconds: 0.1
    )

    #expect(response.model == QwenCompanionDecisionClient.expectedModel)
    #expect(response.action == .support)
    #expect(response.semanticScores.space == 0.82)
    #expect(response.semanticOrderGaps.space == 0.04)
    #expect(response.usage.outputTokens == 0)
    #expect(response.serverLatencyMS == 17)
}

@Test
func qwenCompanionClientFailsExplicitlyForHTTPDecodeModelAndOutputContract() async throws {
    defer { QwenCompanionStubURLProtocol.clearHandler() }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [QwenCompanionStubURLProtocol.self]
    let client = QwenCompanionDecisionClient(urlSession: URLSession(configuration: configuration))

    func decide() async throws -> QwenCompanionDecisionResponse {
        try await client.decide(
            host: "example.com",
            port: 8767,
            state: qwenClientState(),
            timeoutSeconds: 0.1
        )
    }

    QwenCompanionStubURLProtocol.setHandler { request in
        try qwenCompanionHTTPResponse(
            request: request,
            statusCode: 503,
            body: ["code": "busy", "message": "Qwen companion inference is already running"]
        )
    }
    await #expect(
        throws: QwenCompanionDecisionClientError.httpError(
            statusCode: 503,
            code: "busy",
            message: "Qwen companion inference is already running"
        )
    ) {
        _ = try await decide()
    }

    QwenCompanionStubURLProtocol.setHandler { request in
        try qwenCompanionHTTPResponse(
            request: request,
            statusCode: 500,
            body: ["code": "decision_failed", "message": "model failed"]
        )
    }
    await #expect(
        throws: QwenCompanionDecisionClientError.httpError(
            statusCode: 500,
            code: "decision_failed",
            message: "model failed"
        )
    ) {
        _ = try await decide()
    }

    QwenCompanionStubURLProtocol.setHandler { request in
        var body = qwenCompanionDecisionBody(outputTokens: 0)
        body.removeValue(forKey: "semantic_scores")
        return try qwenCompanionHTTPResponse(request: request, statusCode: 200, body: body)
    }
    await #expect(throws: QwenCompanionDecisionClientError.decodeFailed) {
        _ = try await decide()
    }

    QwenCompanionStubURLProtocol.setHandler { request in
        var body = qwenCompanionDecisionBody(outputTokens: 0)
        body["legacy_field"] = true
        return try qwenCompanionHTTPResponse(request: request, statusCode: 200, body: body)
    }
    await #expect(throws: QwenCompanionDecisionClientError.decodeFailed) {
        _ = try await decide()
    }

    QwenCompanionStubURLProtocol.setHandler { request in
        var body = qwenCompanionDecisionBody(outputTokens: 0)
        body["model"] = "other-model"
        return try qwenCompanionHTTPResponse(request: request, statusCode: 200, body: body)
    }
    await #expect(throws: QwenCompanionDecisionClientError.unexpectedModel("other-model")) {
        _ = try await decide()
    }

    QwenCompanionStubURLProtocol.setHandler { request in
        try qwenCompanionHTTPResponse(
            request: request,
            statusCode: 200,
            body: qwenCompanionDecisionBody(outputTokens: 1)
        )
    }
    await #expect(throws: QwenCompanionDecisionClientError.unexpectedOutputTokens(1)) {
        _ = try await decide()
    }
}

private func qwenClientState() -> QwenCompanionState {
    QwenCompanionState(
        heldNotesCount: 1,
        sustainValue: 0,
        recentIOIMedianSeconds: 0.42,
        recentNoteDensityPerSecond: 1.5,
        secondsSinceLastNoteOn: 0.1,
        isAIPlaybackActive: true,
        userNoteOnSinceAIPlaybackStarted: true
    )
}

private func qwenCompanionDecisionBody(outputTokens: Int) -> [String: Any] {
    [
        "model": "Qwen3.5-0.8B-NF4-4bit",
        "action": "support",
        "semantic_scores": [
            "continuing": 0.78,
            "finished": 0.18,
            "space": 0.82,
            "reasserted": 0.12,
        ],
        "semantic_order_gaps": [
            "continuing": 0.03,
            "finished": 0.02,
            "space": 0.04,
            "reasserted": 0.01,
        ],
        "usage": ["input_tokens": 120, "output_tokens": outputTokens],
        "server_latency_ms": 17,
    ]
}

private func qwenCompanionHTTPResponse(
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

private func qwenCompanionHTTPBodyData(from request: URLRequest) -> Data? {
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
