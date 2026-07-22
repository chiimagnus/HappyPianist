import Foundation
import Testing

private struct KnownDeviationManifest: Decodable {
    struct Requirement: Decodable {
        let id: String
        let fixtures: [String]
        let tests: [String]
        let evidenceStatus: String
    }

    let version: Int
    let requirements: [Requirement]
}

@Test
func knownDeviationManifestCoversEveryProfessionalAuditRequirementExactlyOnce() throws {
    let manifestURL = testFixtureURL("PianoPerformanceKnownDeviations.json")
    let manifest = try JSONDecoder().decode(
        KnownDeviationManifest.self,
        from: Data(contentsOf: manifestURL)
    )
    let manifestIDs = manifest.requirements.map(\.id)

    #expect(manifest.version == 1)
    #expect(Set(manifestIDs).count == manifestIDs.count)
    #expect(manifestIDs.count == 54)
    #expect(manifest.requirements.allSatisfy {
        ["missingEvidence", "characterizationPlanned"].contains($0.evidenceStatus)
    })
    #expect(manifest.requirements.allSatisfy { requirement in
        let hasEvidencePath = (requirement.fixtures + requirement.tests).isEmpty == false
        return requirement.evidenceStatus == "missingEvidence" ? hasEvidencePath == false : hasEvidencePath
    })

    let repositoryRoot = repositoryRootURL()
    for requirement in manifest.requirements {
        for path in requirement.fixtures + requirement.tests where path.isEmpty == false {
            #expect(FileManager.default.fileExists(atPath: repositoryRoot.appending(path: path).path()))
        }
    }

}

private func repositoryRootURL(filePath: StaticString = #filePath) -> URL {
    var directory = URL(filePath: "\(filePath)").deletingLastPathComponent()
    while directory.lastPathComponent != "HappyPianistAVPTests", directory.pathComponents.count > 1 {
        directory.deleteLastPathComponent()
    }
    return directory.deletingLastPathComponent()
}
