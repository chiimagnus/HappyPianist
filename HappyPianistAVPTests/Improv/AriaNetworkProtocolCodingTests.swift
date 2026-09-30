import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func ariaNetworkRequestEncodesOnlyCurrentStrictSchema() throws {
    let request = AriaGenerateRequest(
        events: [
            .note(note: 60, velocity: 100, time: 1.25, duration: 0.5),
            .cc(controller: 64, value: 127, time: 1.26),
        ],
        maxTokens: 128
    )

    let data = try JSONEncoder().encode(request)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(Set(json.keys) == ["type", "protocol_version", "events", "params"])
    #expect(json["type"] as? String == "generate")
    #expect(json["protocol_version"] as? Int == AriaNetworkProtocol.version)
    let params = try #require(json["params"] as? [String: Any])
    #expect(Set(params.keys) == ["max_tokens"])
    #expect(params["max_tokens"] as? Int == 128)
    #expect(json["session_id"] == nil)
}

@Test
func ariaNetworkRequestAndResultRoundTripCurrentProtocol() throws {
    let request = AriaGenerateRequest(
        events: [
            .note(note: 48, velocity: 64, time: 0, duration: 0.25),
            .cc(controller: 64, value: 90, time: 0.2),
        ],
        maxTokens: 64
    )
    let requestData = try JSONEncoder().encode(request)
    #expect(try JSONDecoder().decode(AriaGenerateRequest.self, from: requestData) == request)

    let result = AriaResultResponse(events: request.events, latencyMS: 12)
    let resultData = try JSONEncoder().encode(result)
    #expect(try JSONDecoder().decode(AriaResultResponse.self, from: resultData) == result)
}

@Test
func ariaNetworkProtocolRejectsUnknownFieldsWrongVersionAndInvalidEvents() throws {
    let decoder = JSONDecoder()

    let unknownField = Data(#"{"type":"generate","protocol_version":3,"events":[],"params":{"max_tokens":64,"legacy":true}}"#.utf8)
    #expect(throws: DecodingError.self) {
        _ = try decoder.decode(AriaGenerateRequest.self, from: unknownField)
    }

    let wrongVersion = Data(#"{"type":"result","protocol_version":2,"events":[],"latency_ms":1}"#.utf8)
    #expect(throws: DecodingError.self) {
        _ = try decoder.decode(AriaResultResponse.self, from: wrongVersion)
    }

    let invalidNote = Data(#"{"type":"result","protocol_version":3,"events":[{"type":"note","note":200,"velocity":90,"time":0,"duration":0.2}],"latency_ms":1}"#.utf8)
    #expect(throws: DecodingError.self) {
        _ = try decoder.decode(AriaResultResponse.self, from: invalidNote)
    }
}
