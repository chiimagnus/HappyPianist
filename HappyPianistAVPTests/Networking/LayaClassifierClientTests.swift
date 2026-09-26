import Foundation
@testable import HappyPianistAVP
import os
import Testing

private final class LayaClassifierStubURLProtocol: URLProtocol {
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

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

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

private struct LayaClientTestState: Encodable, Sendable {
    let heldNotesCount: Int
    let isAIPlaybackActive: Bool

    enum CodingKeys: String, CodingKey {
        case heldNotesCount = "held_notes_count"
        case isAIPlaybackActive = "is_ai_playback_active"
    }
}

@Test
func layaClassifierClientSendsStructuredStateAndTypedQuestion() async throws {
    defer { LayaClassifierStubURLProtocol.clearHandler() }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LayaClassifierStubURLProtocol.self]
    let client = LayaClassifierClient(
        urlSession: URLSession(configuration: configuration)
    )

    LayaClassifierStubURLProtocol.setHandler { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/classifier")

        let data = try #require(layaClassifierHTTPBodyData(from: request))
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["model"] as? String == "aac6fef/laya-multilingual-mlx")
        let state = try #require(json["state"] as? [String: Any])
        #expect(state["held_notes_count"] as? Int == 1)
        #expect(state["is_ai_playback_active"] as? Bool == true)

        let questions = try #require(json["questions"] as? [String: Any])
        let action = try #require(questions["action"] as? [String: Any])
        #expect(action["type"] as? String == "choice")
        #expect(action["instructions"] as? String == "Choose an action.")
        let criteria = try #require(action["criteria"] as? [String: Any])
        #expect(criteria["listen"] as? String == "Keep listening.")
        #expect(criteria["yield"] as? String == "Yield to the user.")

        return try layaClassifierHTTPResponse(
            request: request,
            statusCode: 200,
            body: layaClassifierChoiceResponse(outputTokens: 0, includeConfidence: true)
        )
    }

    let response = try await client.classify(
        host: "example.com",
        port: 8767,
        model: "aac6fef/laya-multilingual-mlx",
        state: LayaClientTestState(
            heldNotesCount: 1,
            isAIPlaybackActive: true
        ),
        questions: [
            "action": .choice(
                instructions: "Choose an action.",
                criteria: [
                    "listen": "Keep listening.",
                    "yield": "Yield to the user.",
                ]
            ),
        ],
        timeoutSeconds: 1
    )

    let rawAnswer = try #require(response.answers["action"])
    guard case let .choice(answer) = rawAnswer else {
        Issue.record("Expected a choice answer.")
        return
    }
    #expect(answer.choice == "yield")
    #expect(answer.confidence == 0.74)
    #expect(answer.action.actProbability == 0.61)
    #expect(answer.probabilities["yield"] == 0.74)
    #expect(response.usage.outputTokens == 0)
    #expect(response.latencyMS == 17)
}

@Test
func layaClassifierClientEncodesScoreAndNoulAndDecodesTheirAnswers() async throws {
    defer { LayaClassifierStubURLProtocol.clearHandler() }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LayaClassifierStubURLProtocol.self]
    let client = LayaClassifierClient(
        urlSession: URLSession(configuration: configuration)
    )

    LayaClassifierStubURLProtocol.setHandler { request in
        let data = try #require(layaClassifierHTTPBodyData(from: request))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let questions = try #require(json["questions"] as? [String: Any])
        #expect((questions["urgency"] as? [String: Any])?["type"] as? String == "score")
        #expect((questions["supported"] as? [String: Any])?["type"] as? String == "noul")

        return try layaClassifierHTTPResponse(
            request: request,
            statusCode: 200,
            body: [
                "model": "aac6fef/laya-multilingual-mlx",
                "answers": [
                    "urgency": [
                        "type": "score",
                        "score": 1.75,
                        "confidence": 0.51,
                        "action": ["act_probability": 0.44],
                        "legend": ["0": "low", "1": "medium", "2": "high"],
                        "probabilities": ["0": 0.05, "1": 0.15, "2": 0.80],
                    ],
                    "supported": [
                        "type": "noul",
                        "noul": 0.82,
                        "confidence": 0.82,
                        "action": ["act_probability": 0.37],
                    ],
                ],
                "usage": ["input_tokens": 99, "output_tokens": 0],
                "latency_ms": 12,
            ]
        )
    }

    let response = try await client.classify(
        host: "example.com",
        port: 8767,
        model: "aac6fef/laya-multilingual-mlx",
        state: ["signal": "strong"],
        questions: [
            "urgency": .score(
                instructions: "Rate urgency.",
                criteria: ["low", "medium", "high"]
            ),
            "supported": .noul(
                instructions: "Is this supported?",
                trueDescription: "Supported.",
                falseDescription: "Not supported."
            ),
        ],
        timeoutSeconds: 1
    )

    guard case let .score(score) = try #require(response.answers["urgency"]) else {
        Issue.record("Expected a score answer.")
        return
    }
    #expect(score.score == 1.75)
    #expect(score.legend["2"] == "high")
    #expect(score.action.actProbability == 0.44)

    guard case let .noul(noul) = try #require(response.answers["supported"]) else {
        Issue.record("Expected a noul answer.")
        return
    }
    #expect(noul.noul == 0.82)
    #expect(noul.confidence == 0.82)
    #expect(noul.action.actProbability == 0.37)
}

@Test
func layaClassifierClientFailsExplicitlyForBadHTTPMalformedAnswerAndOutputTokens() async throws {
    defer { LayaClassifierStubURLProtocol.clearHandler() }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LayaClassifierStubURLProtocol.self]
    let client = LayaClassifierClient(
        urlSession: URLSession(configuration: configuration)
    )

    func classify() async throws -> LayaClassifierResponse {
        try await client.classify(
            host: "example.com",
            port: 8767,
            model: "aac6fef/laya-multilingual-mlx",
            state: ["value": 1],
            questions: [
                "action": .choice(
                    instructions: "Choose.",
                    criteria: ["listen": nil, "yield": nil]
                ),
            ],
            timeoutSeconds: 1
        )
    }

    LayaClassifierStubURLProtocol.setHandler { request in
        try layaClassifierHTTPResponse(
            request: request,
            statusCode: 500,
            body: ["message": "classification_failed"]
        )
    }
    do {
        _ = try await classify()
        Issue.record("Expected HTTP failure.")
    } catch let error as LayaClassifierClientError {
        #expect(error == .httpError(statusCode: 500, message: "classification_failed"))
    }

    LayaClassifierStubURLProtocol.setHandler { request in
        try layaClassifierHTTPResponse(
            request: request,
            statusCode: 200,
            body: layaClassifierChoiceResponse(outputTokens: 0, includeConfidence: false)
        )
    }
    do {
        _ = try await classify()
        Issue.record("Expected malformed answer to fail decoding.")
    } catch let error as LayaClassifierClientError {
        #expect(error == .decodeFailed)
    }

    LayaClassifierStubURLProtocol.setHandler { request in
        try layaClassifierHTTPResponse(
            request: request,
            statusCode: 200,
            body: layaClassifierChoiceResponse(outputTokens: 1, includeConfidence: true)
        )
    }
    do {
        _ = try await classify()
        Issue.record("Expected non-zero output token count to be rejected.")
    } catch let error as LayaClassifierClientError {
        #expect(error == .unexpectedOutputTokens(1))
    }
}

private func layaClassifierChoiceResponse(
    outputTokens: Int,
    includeConfidence: Bool
) -> [String: Any] {
    var answer: [String: Any] = [
        "type": "choice",
        "choice": "yield",
        "action": ["act_probability": 0.61],
        "probabilities": ["listen": 0.26, "yield": 0.74],
    ]
    if includeConfidence {
        answer["confidence"] = 0.74
    }
    return [
        "model": "aac6fef/laya-multilingual-mlx",
        "answers": ["action": answer],
        "usage": ["input_tokens": 12, "output_tokens": outputTokens],
        "latency_ms": 17,
    ]
}

private func layaClassifierHTTPResponse(
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

private func layaClassifierHTTPBodyData(from request: URLRequest) -> Data? {
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
