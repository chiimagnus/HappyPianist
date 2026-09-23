import Foundation
@testable import HappyPianistAVP
import os
import Testing

private final class JevClassifierStubURLProtocol: URLProtocol {
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

@Test
func jevClassifierClientSendsGenericStateAndTypedQuestion() async throws {
    defer { JevClassifierStubURLProtocol.clearHandler() }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [JevClassifierStubURLProtocol.self]
    let client = JevClassifierClient(
        urlSession: URLSession(configuration: configuration)
    )

    JevClassifierStubURLProtocol.setHandler { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/classifier")

        let data = try #require(jevClassifierHTTPBodyData(from: request))
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["model"] as? String == "Qwen/Qwen3.5-0.8B")
        #expect(json["state"] as? String == #"{"held_notes_count":1}"#)

        let questions = try #require(json["questions"] as? [String: Any])
        let action = try #require(questions["action"] as? [String: Any])
        #expect(action["type"] as? String == "choice")
        #expect(action["instructions"] as? String == "Choose an action.")
        let criteria = try #require(action["criteria"] as? [String: Any])
        #expect(criteria["listen"] as? String == "Keep listening.")
        #expect(criteria["yield"] as? String == "Yield to the user.")

        let responseBody: [String: Any] = [
            "model": "Qwen/Qwen3.5-0.8B",
            "answers": [
                "action": [
                    "type": "choice",
                    "choice": "yield",
                    "confidence": 0.74,
                    "probabilities": [
                        "listen": 0.26,
                        "yield": 0.74,
                    ],
                ],
            ],
            "usage": [
                "input_tokens": 123,
                "output_tokens": 0,
            ],
            "latency_ms": 97,
        ]
        let responseData = try JSONSerialization.data(
            withJSONObject: responseBody
        )
        let url = try #require(request.url)
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, responseData)
    }

    let response = try await client.classify(
        host: "example.com",
        port: 8767,
        model: "Qwen/Qwen3.5-0.8B",
        state: #"{"held_notes_count":1}"#,
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
    #expect(answer.probabilities["yield"] == 0.74)
    #expect(response.usage.outputTokens == 0)
    #expect(response.latencyMS == 97)
}


@Test
func jevClassifierClientDecodesNoulAnswer() async throws {
    defer { JevClassifierStubURLProtocol.clearHandler() }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [JevClassifierStubURLProtocol.self]
    let client = JevClassifierClient(
        urlSession: URLSession(configuration: configuration)
    )

    JevClassifierStubURLProtocol.setHandler { request in
        let data = try #require(jevClassifierHTTPBodyData(from: request))
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let questions = try #require(json["questions"] as? [String: Any])
        let yieldQuestion = try #require(questions["yield"] as? [String: Any])
        #expect(yieldQuestion["type"] as? String == "noul")

        let responseBody: [String: Any] = [
            "model": "Qwen/Qwen3.5-0.8B",
            "answers": [
                "yield": [
                    "type": "noul",
                    "noul": 0.77,
                    "calibrated": false,
                    "rating": [
                        "expected_score": 7.7,
                        "probabilities": [
                            "7": 0.3,
                            "8": 0.7,
                        ],
                    ],
                ],
            ],
            "usage": [
                "input_tokens": 180,
                "output_tokens": 0,
            ],
            "latency_ms": 120,
        ]
        let responseData = try JSONSerialization.data(
            withJSONObject: responseBody
        )
        let url = try #require(request.url)
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, responseData)
    }

    let response = try await client.classify(
        host: "example.com",
        port: 8767,
        model: "Qwen/Qwen3.5-0.8B",
        state: "AI 正在演奏，用户重新进入高密度演奏。",
        questions: [
            "yield": .noul(
                instructions: "AI 是否应该让位？",
                trueDescription: "应该让位。",
                falseDescription: "不应该让位。"
            ),
        ],
        timeoutSeconds: 1
    )

    let rawAnswer = try #require(response.answers["yield"])
    guard case let .noul(answer) = rawAnswer else {
        Issue.record("Expected a Noul answer.")
        return
    }
    #expect(answer.noul == 0.77)
    #expect(answer.calibrated == false)
    #expect(answer.rating.expectedScore == 7.7)
    #expect(answer.rating.probabilities["8"] == 0.7)
    #expect(response.usage.outputTokens == 0)
}

@Test
func jevClassifierClientFailsExplicitlyForBadHTTPMalformedAnswerAndOutputTokens() async throws {
    defer { JevClassifierStubURLProtocol.clearHandler() }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [JevClassifierStubURLProtocol.self]
    let client = JevClassifierClient(
        urlSession: URLSession(configuration: configuration)
    )

    func classify() async throws -> JevClassifierResponse {
        try await client.classify(
            host: "example.com",
            port: 8767,
            model: "Qwen/Qwen3.5-0.8B",
            state: "generic state",
            questions: [
                "route": .choice(
                    instructions: "Choose a route.",
                    criteria: ["a": nil, "b": nil]
                ),
            ],
            timeoutSeconds: 1
        )
    }

    JevClassifierStubURLProtocol.setHandler { request in
        try jevClassifierHTTPResponse(
            request: request,
            statusCode: 500,
            body: ["message": "classification_failed"]
        )
    }
    do {
        _ = try await classify()
        Issue.record("Expected HTTP failure.")
    } catch let error as JevClassifierClientError {
        #expect(error == .httpError(statusCode: 500, message: "classification_failed"))
    }

    JevClassifierStubURLProtocol.setHandler { request in
        try jevClassifierHTTPResponse(
            request: request,
            statusCode: 200,
            body: jevClassifierChoiceResponse(
                outputTokens: 0,
                includeConfidence: false
            )
        )
    }
    do {
        _ = try await classify()
        Issue.record("Expected malformed answer to fail decoding.")
    } catch let error as JevClassifierClientError {
        #expect(error == .decodeFailed)
    }

    JevClassifierStubURLProtocol.setHandler { request in
        try jevClassifierHTTPResponse(
            request: request,
            statusCode: 200,
            body: jevClassifierChoiceResponse(
                outputTokens: 1,
                includeConfidence: true
            )
        )
    }
    do {
        _ = try await classify()
        Issue.record("Expected non-zero output token count to be rejected.")
    } catch let error as JevClassifierClientError {
        #expect(error == .unexpectedOutputTokens(1))
    }
}

private func jevClassifierChoiceResponse(
    outputTokens: Int,
    includeConfidence: Bool
) -> [String: Any] {
    var answer: [String: Any] = [
        "type": "choice",
        "choice": "a",
        "probabilities": ["a": 0.8, "b": 0.2],
    ]
    if includeConfidence {
        answer["confidence"] = 0.8
    }
    return [
        "model": "Qwen/Qwen3.5-0.8B",
        "answers": ["route": answer],
        "usage": ["input_tokens": 12, "output_tokens": outputTokens],
        "latency_ms": 4,
    ]
}

private func jevClassifierHTTPResponse(
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

private func jevClassifierHTTPBodyData(from request: URLRequest) -> Data? {
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
