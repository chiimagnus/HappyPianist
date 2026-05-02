@testable import LonelyPianistAVP
import Foundation
import Testing

@Test
func improvGenerateRequestUsesSnakeCaseKeys() throws {
    let request = ImprovGenerateRequest(
        notes: [
            ImprovDialogueNote(note: 60, velocity: 90, time: 0.0, duration: 0.5),
        ],
        params: ImprovGenerateParams(topP: 0.9, maxTokens: 128, strategy: "deterministic"),
        sessionID: "s1"
    )

    let data = try JSONEncoder().encode(request)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["type"] as? String == "generate")
    #expect(json["protocol_version"] as? Int == 1)
    #expect(json["session_id"] as? String == "s1")

    let params = try #require(json["params"] as? [String: Any])
    #expect(params["strategy"] as? String == "deterministic")
    #expect(params["max_tokens"] as? Int == 128)
    #expect(params["top_p"] as? Double == 0.9)
}

@Test
func improvResultResponseDecodesNotes() throws {
    let data = Data(
        """
        {
          "type": "result",
          "protocol_version": 1,
          "notes": [{"note": 60, "velocity": 80, "time": 0.0, "duration": 0.25}],
          "latency_ms": 12
        }
        """.utf8
    )

    let decoded = try JSONDecoder().decode(ImprovResultResponse.self, from: data)
    #expect(decoded.type == "result")
    #expect(decoded.protocolVersion == 1)
    #expect(decoded.latencyMS == 12)
    #expect(decoded.notes.count == 1)
    #expect(decoded.notes[0].note == 60)
}

