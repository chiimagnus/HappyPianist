import Foundation

struct PianoPerformanceCorpusFixture: Equatable {
    let id: String
    let semanticTags: [String]
    let url: URL
}

enum PianoPerformanceCorpusFixtureLoaderError: Error, LocalizedError {
    case duplicateFixtureID(String)
    case missingProfessionalManifest
    case missingProfessionalFixtureFile(String)

    var errorDescription: String? {
        switch self {
        case let .duplicateFixtureID(id):
            "duplicate corpus fixture id: \(id)"
        case .missingProfessionalManifest:
            "PianoPerformanceFixtureManifest.json does not declare professionalCorpusManifest"
        case let .missingProfessionalFixtureFile(id):
            "available professional corpus fixture has no file: \(id)"
        }
    }
}

struct PianoPerformanceCorpusFixtureLoader {
    private struct Manifest: Decodable {
        struct Fixture: Decodable {
            let id: String
            let status: String
            let file: String?
            let semanticTags: [String]
        }

        let fixtures: [Fixture]
    }

    func load() throws -> [PianoPerformanceCorpusFixture] {
        let rootManifest = try PianoPerformanceFixtureLoader().load()
        let rootFixtures = rootManifest.fixtures.map { fixture in
            PianoPerformanceCorpusFixture(
                id: fixture.id,
                semanticTags: fixture.coverage,
                url: testFixtureURL(fixture.file)
            )
        }
        guard let manifestPath = rootManifest.professionalCorpusManifest else {
            throw PianoPerformanceCorpusFixtureLoaderError.missingProfessionalManifest
        }

        let professionalRoot = testFixtureURL(manifestPath).deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(
            Manifest.self,
            from: Data(contentsOf: testFixtureURL(manifestPath))
        )
        let professionalFixtures = try manifest.fixtures
            .filter { $0.status == "available" }
            .map { fixture in
                guard let file = fixture.file else {
                    throw PianoPerformanceCorpusFixtureLoaderError.missingProfessionalFixtureFile(fixture.id)
                }
                return PianoPerformanceCorpusFixture(
                    id: fixture.id,
                    semanticTags: fixture.semanticTags,
                    url: professionalRoot.appending(path: file)
                )
            }
        let fixtures = rootFixtures + professionalFixtures
        guard Set(fixtures.map(\.id)).count == fixtures.count else {
            throw PianoPerformanceCorpusFixtureLoaderError.duplicateFixtureID(
                Dictionary(grouping: fixtures, by: \.id).first { $0.value.count > 1 }?.key ?? "unknown"
            )
        }
        return fixtures
    }
}
