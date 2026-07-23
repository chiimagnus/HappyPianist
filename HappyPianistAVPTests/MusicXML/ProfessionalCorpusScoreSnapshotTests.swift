import CryptoKit
import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func professionalCorpusScoreSnapshotsMatchReviewedFingerprints() throws {
    let fixtures = try PianoPerformanceCorpusFixtureLoader().load()
    let actual = try fixtures.map(makeSnapshotBaseline).sorted { $0.fixtureID < $1.fixtureID }

    let expected = try JSONDecoder().decode(
        CorpusScoreSnapshotBaseline.self,
        from: Data(contentsOf: testFixtureURL("ProfessionalCorpus/score-snapshots.json"))
    )
    #expect(expected.version == 1)
    #expect(expected.snapshots.map(\.fixtureID).sorted() == actual.map(\.fixtureID))

    let expectedByFixture = Dictionary(uniqueKeysWithValues: expected.snapshots.map { ($0.fixtureID, $0) })
    for snapshot in actual {
        let baseline = try #require(expectedByFixture[snapshot.fixtureID])
        #expect(baseline.requirementID == snapshot.requirementID)
        try assertFingerprint(baseline.sourceFacts, snapshot.sourceFacts, snapshot: "sourceFacts", for: snapshot)
        try assertFingerprint(baseline.normalization, snapshot.normalization, snapshot: "normalization", for: snapshot)
        try assertFingerprint(baseline.performedOrder, snapshot.performedOrder, snapshot: "performedOrder", for: snapshot)
        try assertFingerprint(baseline.notation, snapshot.notation, snapshot: "notation", for: snapshot)
    }
}

private struct CorpusScoreSnapshotBaseline: Codable {
    let version: Int
    let snapshots: [FixtureScoreSnapshotBaseline]
}

private struct FixtureScoreSnapshotBaseline: Codable {
    let fixtureID: String
    let requirementID: String
    let sourceFacts: CorpusSnapshotFingerprint
    let normalization: CorpusSnapshotFingerprint
    let performedOrder: CorpusSnapshotFingerprint
    let notation: CorpusSnapshotFingerprint
}

private struct CorpusSnapshotFingerprint: Codable, Equatable {
    let lineCount: Int
    let sha256: String
}

private enum CorpusScoreSnapshotError: Error, LocalizedError {
    case mismatch(
        fixtureID: String,
        requirementID: String,
        snapshot: String,
        expected: CorpusSnapshotFingerprint,
        actual: CorpusSnapshotFingerprint
    )

    var errorDescription: String? {
        switch self {
        case let .mismatch(fixtureID, requirementID, snapshot, expected, actual):
            "fixture=\(fixtureID) requirement=\(requirementID) snapshot=\(snapshot) expected(lines=\(expected.lineCount),sha256=\(expected.sha256)) actual(lines=\(actual.lineCount),sha256=\(actual.sha256))"
        }
    }
}

private func makeSnapshotBaseline(_ fixture: PianoPerformanceCorpusFixture) throws -> FixtureScoreSnapshotBaseline {
    let parsed = try MusicXMLParser().parse(fileURL: fixture.url)
    let normalized = MusicXMLPianoGrandStaffNormalizer().normalize(score: parsed)
    let includedPartIDs = Set(normalized.notes.map(\.partID))
    let primaryPartID = normalized.logicalInstruments.first?.memberPartIDs.first
        ?? normalized.notes.first?.partID
        ?? "P1"
    let performedOrder = MusicXMLStructureExpander().expandStructureIfPossible(
        score: normalized,
        primaryPartID: primaryPartID,
        includedPartIDs: includedPartIDs
    )
    let plan = makeTestScorePerformancePlan(
        from: performedOrder.score,
        performanceTimingEnabled: true
    )
    let notation = ScoreNotationProjection(plan: plan, sourceScore: normalized)
    let snapshot = MusicXMLScoreSnapshot()

    return FixtureScoreSnapshotBaseline(
        fixtureID: fixture.id,
        requirementID: "P15-CORPUS-SCORE-\(fixture.id)",
        sourceFacts: fingerprint(snapshot.encode(parsed)),
        normalization: fingerprint(snapshot.encodeNormalization(normalized)),
        performedOrder: fingerprint(snapshot.encodePerformedOrder(performedOrder)),
        notation: fingerprint(snapshot.encodeNotation(notation))
    )
}

private func fingerprint(_ snapshot: String) -> CorpusSnapshotFingerprint {
    let digest = SHA256.hash(data: Data(snapshot.utf8))
    let sha256 = digest.map { byte in
        let value = String(byte, radix: 16, uppercase: false)
        return String(repeating: "0", count: max(0, 2 - value.count)) + value
    }.joined()
    return CorpusSnapshotFingerprint(
        lineCount: snapshot.isEmpty ? 0 : snapshot.split(separator: "\n", omittingEmptySubsequences: false).count,
        sha256: sha256
    )
}

private func assertFingerprint(
    _ expected: CorpusSnapshotFingerprint,
    _ actual: CorpusSnapshotFingerprint,
    snapshot: String,
    for fixture: FixtureScoreSnapshotBaseline
) throws {
    guard expected == actual else {
        throw CorpusScoreSnapshotError.mismatch(
            fixtureID: fixture.fixtureID,
            requirementID: fixture.requirementID,
            snapshot: snapshot,
            expected: expected,
            actual: actual
        )
    }
}
