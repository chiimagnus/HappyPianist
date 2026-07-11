import Foundation
@testable import LonelyPianistAVP
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

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

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
func improvBackendClientV2RoundTripAndScheduleHasControlChange() async throws {
    defer { StubURLProtocol.clearHandler() }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    let client = ImprovBackendClient(urlSession: session)

    StubURLProtocol.setHandler { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/generate")

        let bodyData = try #require(readHTTPBodyData(from: request))
        let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(json["protocol_version"] as? Int == 2)
        #expect((json["session_id"] as? String) == "session-v2")

        let events = try #require(json["events"] as? [[String: Any]])
        #expect(events.isEmpty == false)

        let responseBody: [String: Any] = [
            "type": "result",
            "protocol_version": 2,
            "latency_ms": 123,
            "events": [
                ["type": "cc", "controller": 64, "value": 127, "time": 0.0],
                ["type": "note", "note": 60, "velocity": 90, "time": 0.0, "duration": 0.2],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: responseBody, options: [])
        let url = try #require(request.url)
        let httpResponse = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (httpResponse, data)
    }

    let request = ImprovGenerateRequestV2(
        events: [
            .cc(controller: 64, value: 127, time: 0),
            .note(note: 60, velocity: 90, time: 0, duration: 0.2),
        ],
        params: ImprovGenerateParams(topP: 0.9, maxTokens: 64, strategy: "test"),
        sessionID: "session-v2"
    )

    let response = try await client.generateV2(host: "example.com", port: 8766, request: request, timeoutSeconds: 2)
    #expect(response.latencyMS == 123)

    let schedule = ImprovScheduleBuilder().buildSchedule(from: response.events, leadInSeconds: 0)
    #expect(schedule.contains(where: { event in
        if case let .controlChange(controller, _) = event.kind { return controller == 64 }
        return false
    }))
}

private func readHTTPBodyData(from request: URLRequest) -> Data? {
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
        let readCount = stream.read(&buffer, maxLength: buffer.count)
        guard readCount > 0 else { break }
        data.append(buffer, count: readCount)
    }

    return data
}
