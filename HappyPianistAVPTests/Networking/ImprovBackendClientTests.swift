import Foundation
@testable import HappyPianistAVP
import os
import Testing

private final class StubURLProtocol: URLProtocol {
    struct State {
        var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    }

    private static let lock = OSAllocatedUnfairLock(initialState: State())

    static func setHandler(_ handler: @Sendable @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
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
func improvBackendClientUsesCurrentAriaSchemaAndDecodesResult() async throws {
    defer { StubURLProtocol.clearHandler() }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let client = ImprovBackendClient(urlSession: URLSession(configuration: config))

    StubURLProtocol.setHandler { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == AriaNetworkProtocol.path)
        #expect(request.timeoutInterval == 0.35)

        let bodyData = try #require(readHTTPBodyData(from: request))
        let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(Set(json.keys) == ["type", "protocol_version", "events", "params"])
        #expect(json["protocol_version"] as? Int == AriaNetworkProtocol.version)
        #expect(json["session_id"] == nil)
        let params = try #require(json["params"] as? [String: Any])
        #expect(Set(params.keys) == ["max_tokens"])
        #expect(params["max_tokens"] as? Int == 64)

        return try httpResponse(
            request: request,
            statusCode: 200,
            body: [
                "type": "result",
                "protocol_version": AriaNetworkProtocol.version,
                "latency_ms": 123,
                "events": [
                    ["type": "cc", "controller": 64, "value": 127, "time": 0.0],
                    ["type": "note", "note": 60, "velocity": 90, "time": 0.0, "duration": 0.2],
                ],
            ]
        )
    }

    let response = try await client.generate(
        host: "example.com",
        port: 8766,
        request: AriaGenerateRequest(
            events: [
                .cc(controller: 64, value: 127, time: 0),
                .note(note: 60, velocity: 90, time: 0, duration: 0.2),
            ],
            maxTokens: 64
        ),
        timeoutSeconds: 0.35
    )

    #expect(response.latencyMS == 123)
    #expect(response.events.count == 2)
}

@Test
func improvBackendClientSurfacesTypedBusyAndRejectsMalformedSuccess() async throws {
    defer { StubURLProtocol.clearHandler() }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let client = ImprovBackendClient(urlSession: URLSession(configuration: config))
    let request = AriaGenerateRequest(
        events: [.note(note: 60, velocity: 90, time: 0, duration: 0.2)],
        maxTokens: 64
    )

    StubURLProtocol.setHandler { request in
        try httpResponse(
            request: request,
            statusCode: 503,
            body: [
                "type": "error",
                "protocol_version": AriaNetworkProtocol.version,
                "code": "busy",
                "message": "Aria inference is already running",
            ]
        )
    }
    await #expect(
        throws: ImprovBackendClientError.httpError(
            statusCode: 503,
            code: "busy",
            message: "Aria inference is already running"
        )
    ) {
        _ = try await client.generate(host: "example.com", port: 8766, request: request, timeoutSeconds: 0.35)
    }

    StubURLProtocol.setHandler { request in
        try httpResponse(
            request: request,
            statusCode: 200,
            body: [
                "type": "error",
                "protocol_version": AriaNetworkProtocol.version,
                "code": "busy",
            ]
        )
    }
    await #expect(throws: ImprovBackendClientError.decodeFailed) {
        _ = try await client.generate(host: "example.com", port: 8766, request: request, timeoutSeconds: 0.35)
    }
}

private func httpResponse(
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

private func readHTTPBodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
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
