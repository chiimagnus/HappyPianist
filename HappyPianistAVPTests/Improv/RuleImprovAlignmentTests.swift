import Foundation
@testable import HappyPianistAVP
import Testing

private struct RuleFixture: Decodable {
    struct Note: Decodable {
        let note: Int
        let velocity: Int
        let time: Double
        let duration: Double

        var domain: ImprovDialogueNote {
            ImprovDialogueNote(note: note, velocity: velocity, time: time, duration: duration)
        }
    }

    let notes: [Note]
    let topP: Double
    let maxTokens: Int
    let seed: UInt64
    let expectedNotes: [Note]

    enum CodingKeys: String, CodingKey {
        case notes
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case seed
        case expectedNotes = "expected_notes"
    }
}

@Test
func ruleFixture1AlignsWithinTolerance() throws {
    let fixture = try loadFixture(name: "rule-fixture-1")
    let generator = RuleImprovGenerator()
    let actual = generator.generateRuleResponse(
        notes: fixture.notes.map(\.domain),
        params: ImprovGenerateParams(
            topP: fixture.topP,
            maxTokens: fixture.maxTokens,
            seed: fixture.seed
        )
    )
    let expected = fixture.expectedNotes.map(\.domain)

    #expect(actual.count == expected.count)
    for (lhs, rhs) in zip(actual, expected) {
        #expect(lhs.note == rhs.note)
        #expect(lhs.velocity == rhs.velocity)
        #expect(abs(lhs.time - rhs.time) <= 1e-3)
        #expect(abs(lhs.duration - rhs.duration) <= 1e-3)
    }
}

private func loadFixture(name: String) throws -> RuleFixture {
    let baseURL = URL(filePath: #filePath).deletingLastPathComponent()
    let fixtureURL = baseURL.appending(path: "RuleFixtures").appending(path: "\(name).json")
    return try JSONDecoder().decode(RuleFixture.self, from: Data(contentsOf: fixtureURL))
}
