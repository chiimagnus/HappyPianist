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
    func load(filePath: StaticString = #filePath) throws -> PianoPerformanceFixtureManifest {
        let manifestURL = testFixtureURL("PianoPerformanceFixtureManifest.json", filePath: filePath)
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(PianoPerformanceFixtureManifest.self, from: data)
        try validate(manifest, filePath: filePath)
        return manifest
    }

    func fixture(
        id: String,
        filePath: StaticString = #filePath
    ) throws -> (metadata: PianoPerformanceFixture, url: URL) {
        let manifest = try load(filePath: filePath)
        let metadata = try #require(manifest.fixtures.first { $0.id == id })
        return (metadata, testFixtureURL(metadata.file, filePath: filePath))
    }

    private func validate(
        _ manifest: PianoPerformanceFixtureManifest,
        filePath: StaticString
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
                atPath: testFixtureURL(fixture.file, filePath: filePath).path
            ) else {
                throw PianoPerformanceFixtureLoaderError.missingFixture(fixture.file)
            }
        }

        let fixtureDirectory = testFixtureURL("PianoPerformanceFixtureManifest.json", filePath: filePath)
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
