import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func v2RequestEncodesStableSchema() throws {
    let request = ImprovGenerateRequestV2(
        events: [
            .note(note: 60, velocity: 100, time: 1.25, duration: 0.5),
            .cc(controller: 64, value: 127, time: 1.26),
        ],
        params: ImprovGenerateParams(topP: 0.9, maxTokens: 128, strategy: "test"),
        sessionID: "session-1"
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(request)

    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["type"] as? String == "generate")
    #expect(json["protocol_version"] as? Int == 2)
    #expect(json["session_id"] as? String == "session-1")
    #expect(json["params"] != nil)

    let events = try #require(json["events"] as? [[String: Any]])
    #expect(events.count == 2)

    let noteEvent = events[0]
    #expect(noteEvent["type"] as? String == "note")
    #expect(Set(noteEvent.keys) == ["type", "note", "velocity", "time", "duration"])

    let ccEvent = events[1]
    #expect(ccEvent["type"] as? String == "cc")
    #expect(Set(ccEvent.keys) == ["type", "controller", "value", "time"])
}

@Test
func v2RequestRoundTripDecodeMatches() throws {
    let request = ImprovGenerateRequestV2(
        events: [
            .note(note: 48, velocity: 64, time: 0, duration: 0.25),
            .cc(controller: 7, value: 80, time: 0.1),
            .cc(controller: 11, value: 90, time: 0.2),
        ],
        params: ImprovGenerateParams(topP: 0.5, maxTokens: 64, strategy: "test-2", seed: 42),
        sessionID: "session-2"
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(request)

    let decoded = try JSONDecoder().decode(ImprovGenerateRequestV2.self, from: data)
    #expect(decoded == request)
}
