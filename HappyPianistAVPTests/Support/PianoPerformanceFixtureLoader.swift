import Foundation
import Testing

struct PianoPerformanceFixtureManifest: Decodable, Equatable {
    let version: Int
    let professionalCorpusManifest: String?
    let fixtures: [PianoPerformanceFixture]
}

struct PianoPerformanceFixture: Decodable, Equatable, Identifiable {
    let id: String
    let file: String
    let source: String
    let license: String
    let exporter: String
    let coverage: [String]
    let snapshot: String
}

enum PianoPerformanceFixtureLoaderError: Error, Equatable {
    case duplicateID(String)
    case duplicateFile(String)
    case missingFixture(String)
    case unregisteredFixture(String)
}

struct PianoPerformanceFixtureLoader {
    func load() throws -> PianoPerformanceFixtureManifest {
        let manifestURL = testFixtureURL("PianoPerformanceFixtureManifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(PianoPerformanceFixtureManifest.self, from: data)
        try validate(manifest)
        return manifest
    }

    func fixture(
        id: String
    ) throws -> (metadata: PianoPerformanceFixture, url: URL) {
        let manifest = try load()
        let metadata = try #require(manifest.fixtures.first { $0.id == id })
        return (metadata, testFixtureURL(metadata.file))
    }

    private func validate(
        _ manifest: PianoPerformanceFixtureManifest
    ) throws {
        var ids: Set<String> = []
        var files: Set<String> = []
        for fixture in manifest.fixtures {
            guard ids.insert(fixture.id).inserted else {
                throw PianoPerformanceFixtureLoaderError.duplicateID(fixture.id)
            }
            guard files.insert(fixture.file).inserted else {
                throw PianoPerformanceFixtureLoaderError.duplicateFile(fixture.file)
            }
            guard FileManager.default.fileExists(
                atPath: testFixtureURL(fixture.file).path
            ) else {
                throw PianoPerformanceFixtureLoaderError.missingFixture(fixture.file)
            }
        }

        let fixtureDirectory = testFixtureURL("PianoPerformanceFixtureManifest.json")
            .deletingLastPathComponent()
        let discoveredFiles = try FileManager.default.contentsOfDirectory(
            at: fixtureDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { ["musicxml", "xml", "mxl"].contains($0.pathExtension.lowercased()) }
        .map(\.lastPathComponent)

        if let unregistered = discoveredFiles.first(where: { files.contains($0) == false }) {
            throw PianoPerformanceFixtureLoaderError.unregisteredFixture(unregistered)
        }
    }
}
