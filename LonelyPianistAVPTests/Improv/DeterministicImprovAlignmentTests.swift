@testable import LonelyPianistAVP
import Foundation
import ImprovEngines
import ImprovProtocol
import Testing

private struct DeterministicFixture: Codable, Sendable {
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
func deterministicFixture1AlignsWithinTolerance() throws {
    let fixture = try loadFixture(name: "fixture-1")
    let generator = DeterministicImprovGenerator()

    let actual = generator.generateDeterministicResponse(
        notes: fixture.notes,
        params: fixture.params,
        seed: fixture.params.seed
    )

    #expect(actual.count == fixture.expectedNotes.count)
    for (lhs, rhs) in zip(actual, fixture.expectedNotes) {
        #expect(lhs.note == rhs.note)
        #expect(lhs.velocity == rhs.velocity)
        #expect(abs(lhs.time - rhs.time) <= 1e-3)
        #expect(abs(lhs.duration - rhs.duration) <= 1e-3)
    }
}

private func loadFixture(name: String) throws -> DeterministicFixture {
    let baseURL = URL(filePath: #filePath).deletingLastPathComponent()
    let fixtureURL = baseURL.appending(path: "DeterministicFixtures").appending(path: "\(name).json")
    let data = try Data(contentsOf: fixtureURL)
    return try JSONDecoder().decode(DeterministicFixture.self, from: data)
}
