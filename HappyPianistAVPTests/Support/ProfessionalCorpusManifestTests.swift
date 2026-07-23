import Foundation
import Testing

@Test
func professionalCorpusManifestIsRegisteredAndValid() throws {
    let fixturesRoot = testFixtureURL("ProfessionalCorpus")
    let manifestURL = fixturesRoot.appending(path: "manifest.json")
    let manifest = try JSONDecoder().decode(
        ProfessionalCorpusManifest.self,
        from: Data(contentsOf: manifestURL)
    )
    let rootManifest = try JSONDecoder().decode(
        PianoPerformanceFixtureManifestIndex.self,
        from: Data(contentsOf: testFixtureURL("PianoPerformanceFixtureManifest.json"))
    )

    #expect(rootManifest.professionalCorpusManifest == "ProfessionalCorpus/manifest.json")
    try ProfessionalCorpusManifestValidator.validate(
        manifest,
        discoveredFiles: ProfessionalCorpusManifestValidator.discoveredFixtureFiles(at: fixturesRoot),
        fileExists: { file in
            FileManager.default.fileExists(atPath: fixturesRoot.appending(path: file).path())
        }
    )
}

@Test
func professionalCorpusManifestRejectsIncompleteDuplicateAndUnregisteredFixtures() throws {
    let valid = ProfessionalCorpusFixture(
        id: "fixture",
        status: "available",
        file: "MuseScore/fixture.musicxml",
        exporter: .init(name: "MuseScore", version: "4.4"),
        source: "project-owned source score",
        license: "CC0-1.0",
        semanticTags: ["pedal"],
        expectedOutputs: ["source-facts"],
        distributionScope: "repository test asset",
        blockedReason: nil
    )

    #expect(throws: ProfessionalCorpusManifestError.missingRequiredField("fixture", "license")) {
        try ProfessionalCorpusManifestValidator.validate(
            .init(version: 1, fixtures: [
                .init(
                    id: valid.id,
                    status: valid.status,
                    file: valid.file,
                    exporter: valid.exporter,
                    source: valid.source,
                    license: "",
                    semanticTags: valid.semanticTags,
                    expectedOutputs: valid.expectedOutputs,
                    distributionScope: valid.distributionScope,
                    blockedReason: valid.blockedReason
                ),
            ]),
            discoveredFiles: [valid.file!],
            fileExists: { _ in true }
        )
    }

    #expect(throws: ProfessionalCorpusManifestError.duplicateID("fixture")) {
        try ProfessionalCorpusManifestValidator.validate(
            .init(version: 1, fixtures: [valid, valid]),
            discoveredFiles: [valid.file!],
            fileExists: { _ in true }
        )
    }

    #expect(throws: ProfessionalCorpusManifestError.unregisteredFixture("MuseScore/unregistered.musicxml")) {
        try ProfessionalCorpusManifestValidator.validate(
            .init(version: 1, fixtures: [valid]),
            discoveredFiles: ["MuseScore/unregistered.musicxml"],
            fileExists: { _ in true }
        )
    }
}

private struct PianoPerformanceFixtureManifestIndex: Decodable {
    let professionalCorpusManifest: String
}

private struct ProfessionalCorpusManifest: Decodable {
    let version: Int
    let fixtures: [ProfessionalCorpusFixture]
}

private struct ProfessionalCorpusFixture: Decodable, Equatable {
    struct Exporter: Decodable, Equatable {
        let name: String
        let version: String
    }

    let id: String
    let status: String
    let file: String?
    let exporter: Exporter
    let source: String
    let license: String
    let semanticTags: [String]
    let expectedOutputs: [String]
    let distributionScope: String
    let blockedReason: String?
}

private enum ProfessionalCorpusManifestError: Error, Equatable {
    case duplicateID(String)
    case duplicateFile(String)
    case missingFixture(String)
    case unregisteredFixture(String)
    case missingRequiredField(String, String)
    case invalidStatus(String, String)
    case blockedFixtureHasFile(String)
    case blockedFixtureMissingReason(String)
    case unavailableLicense(String)
}

private enum ProfessionalCorpusManifestValidator {
    static func validate(
        _ manifest: ProfessionalCorpusManifest,
        discoveredFiles: [String],
        fileExists: (String) -> Bool
    ) throws {
        var ids: Set<String> = []
        var files: Set<String> = []

        for fixture in manifest.fixtures {
            try require(fixture.id, named: "id", for: fixture.id)
            try require(fixture.exporter.name, named: "exporter.name", for: fixture.id)
            try require(fixture.exporter.version, named: "exporter.version", for: fixture.id)
            try require(fixture.source, named: "source", for: fixture.id)
            try require(fixture.license, named: "license", for: fixture.id)
            try require(fixture.distributionScope, named: "distributionScope", for: fixture.id)
            guard fixture.semanticTags.isEmpty == false else {
                throw ProfessionalCorpusManifestError.missingRequiredField(fixture.id, "semanticTags")
            }
            guard fixture.expectedOutputs.isEmpty == false else {
                throw ProfessionalCorpusManifestError.missingRequiredField(fixture.id, "expectedOutputs")
            }
            guard ids.insert(fixture.id).inserted else {
                throw ProfessionalCorpusManifestError.duplicateID(fixture.id)
            }

            switch fixture.status {
            case "available":
                guard let file = fixture.file, file.isEmpty == false else {
                    throw ProfessionalCorpusManifestError.missingRequiredField(fixture.id, "file")
                }
                guard files.insert(file).inserted else {
                    throw ProfessionalCorpusManifestError.duplicateFile(file)
                }
                guard fixture.license.localizedCaseInsensitiveCompare("unknown") != .orderedSame,
                      fixture.license.localizedCaseInsensitiveCompare("not acquired") != .orderedSame
                else {
                    throw ProfessionalCorpusManifestError.unavailableLicense(fixture.id)
                }
                guard fileExists(file) else {
                    throw ProfessionalCorpusManifestError.missingFixture(file)
                }
            case "blocked":
                guard fixture.file == nil else {
                    throw ProfessionalCorpusManifestError.blockedFixtureHasFile(fixture.id)
                }
                guard let reason = fixture.blockedReason, reason.isEmpty == false else {
                    throw ProfessionalCorpusManifestError.blockedFixtureMissingReason(fixture.id)
                }
            default:
                throw ProfessionalCorpusManifestError.invalidStatus(fixture.id, fixture.status)
            }
        }

        if let unregistered = discoveredFiles.first(where: { files.contains($0) == false }) {
            throw ProfessionalCorpusManifestError.unregisteredFixture(unregistered)
        }
    }

    static func discoveredFixtureFiles(at root: URL) -> [String] {
        let prefix = root.path() + "/"
        return (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { ["musicxml", "xml", "mxl"].contains($0.pathExtension.lowercased()) }
            .map { $0.path().replacingOccurrences(of: prefix, with: "") }
            .sorted()
    }

    private static func require(_ value: String, named field: String, for fixtureID: String) throws {
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ProfessionalCorpusManifestError.missingRequiredField(fixtureID, field)
        }
    }
}
