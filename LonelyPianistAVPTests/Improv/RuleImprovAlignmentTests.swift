import Foundation
import ImprovEngines
import ImprovProtocol
@testable import LonelyPianistAVP
import Testing

private struct RuleFixture: Codable {
    var notes: [ImprovDialogueNote]
    var params: ImprovGenerateParams
    var sessionID: String?
    var expectedNotes: [ImprovDialogueNote]

    enum CodingKeys: String, CodingKey {
        case notes
        case params
        case sessionID = "session_id"
        case expectedNotes = "expected_notes"
    }
}

@Test
func ruleFixture1AlignsWithinTolerance() throws {
    let fixture = try loadFixture(name: "rule-fixture-1")
    let seed = try #require(fixture.params.seed)

    let generator = RuleImprovGenerator()
    let actual = generator.generateRuleResponse(
        notes: fixture.notes,
        params: fixture.params,
        sessionID: fixture.sessionID,
        seed: seed
    )

    #expect(actual.count == fixture.expectedNotes.count)
    for (lhs, rhs) in zip(actual, fixture.expectedNotes) {
        #expect(lhs.note == rhs.note)
        #expect(lhs.velocity == rhs.velocity)
        #expect(abs(lhs.time - rhs.time) <= 1e-3)
        #expect(abs(lhs.duration - rhs.duration) <= 1e-3)
    }
}

private func loadFixture(name: String) throws -> RuleFixture {
    let baseURL = URL(filePath: #filePath).deletingLastPathComponent()
    let fixtureURL = baseURL.appending(path: "RuleFixtures").appending(path: "\(name).json")
    let data = try Data(contentsOf: fixtureURL)
    return try JSONDecoder().decode(RuleFixture.self, from: data)
}
