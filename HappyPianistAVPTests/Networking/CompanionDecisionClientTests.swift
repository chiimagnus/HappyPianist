import Foundation
@testable import HappyPianistAVP
import os
import Testing

private final class CompanionDecisionStubURLProtocol: URLProtocol {
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
func companionDecisionClientSendsStructuredMIDIContextAndDecodesProbabilities() async throws {
    defer { CompanionDecisionStubURLProtocol.clearHandler() }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CompanionDecisionStubURLProtocol.self]
    let client = CompanionDecisionClient(
        urlSession: URLSession(configuration: configuration)
    )

    CompanionDecisionStubURLProtocol.setHandler { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/decision")

        let data = try #require(companionDecisionHTTPBodyData(from: request))
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["protocol_version"] as? Int == 1)

        let input = try #require(json["input"] as? [String: Any])
        #expect(input["held_notes_count"] as? Int == 1)
        #expect(input["is_ai_playback_active"] as? Bool == true)
        let notes = try #require(input["recent_notes"] as? [[String: Any]])
        #expect(notes.count == 1)
        #expect(notes[0]["midi"] as? Int == 64)
        #expect(notes[0]["onset_seconds_ago"] as? Double == 0.4)

        let responseBody: [String: Any] = [
            "protocol_version": 1,
            "action": "yield",
            "confidence": 0.74,
            "probabilities": [
                "listen": 0.1,
                "support": 0.05,
                "sparse": 0.05,
                "yield": 0.74,
                "respond": 0.06,
            ],
            "latency_ms": 97,
            "model": "Qwen/Qwen3.5-0.8B",
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

    let response = try await client.decide(
        host: "example.com",
        port: 8767,
        input: CompanionDecisionInput(
            nowTimestampSeconds: 10,
            heldNotesCount: 1,
            sustainValue: 127,
            recentIOIMedianSeconds: 0.2,
            recentVelocityTrend: 3,
            recentNoteDensityPerSecond: 2,
            lastUserEventTimestampSeconds: 9.9,
            lastNoteOnTimestampSeconds: 9.8,
            activePitchCenter: 64,
            isAIPlaybackActive: true,
            recentNotes: [
                CompanionDecisionNote(
                    midi: 64,
                    velocity: 90,
                    onsetSecondsAgo: 0.4,
                    durationSeconds: 0.3
                ),
            ]
        ),
        timeoutSeconds: 1
    )

    #expect(response.action == .yield)
    #expect(response.confidence == 0.74)
    #expect(response.probabilities["yield"] == 0.74)
    #expect(response.latencyMS == 97)
}

private func companionDecisionHTTPBodyData(from request: URLRequest) -> Data? {
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
