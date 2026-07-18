import Foundation
import Testing

private struct KnownDeviationManifest: Decodable {
    struct Requirement: Decodable {
        let id: String
        let plannedTask: String
        let fixtures: [String]
        let tests: [String]
        let evidenceStatus: String
    }

    let version: Int
    let sourceDocument: String
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
    #expect(manifest.requirements.allSatisfy { $0.plannedTask.range(
        of: #"^P\d+-T\d+$"#,
        options: .regularExpression
    ) != nil })
    #expect(manifest.requirements.allSatisfy {
        ["missingEvidence", "characterizationPlanned"].contains($0.evidenceStatus)
    })
    #expect(manifest.requirements.allSatisfy { requirement in
        let hasEvidencePath = (requirement.fixtures + requirement.tests).isEmpty == false
        return requirement.evidenceStatus == "missingEvidence" ? hasEvidencePath == false : hasEvidencePath
    })

    let repositoryRoot = repositoryRootURL()
    let plannedTaskIDs = try ["todo1.toml", "todo2.toml"].reduce(into: Set<String>()) { result, fileName in
        let text = try String(
            contentsOf: repositoryRoot
                .appending(path: ".github/features/professional-piano-performance")
                .appending(path: fileName),
            encoding: .utf8
        )
        result.formUnion(taskIDs(in: text))
    }
    for requirement in manifest.requirements {
        #expect(plannedTaskIDs.contains(requirement.plannedTask))
        for path in requirement.fixtures + requirement.tests where path.isEmpty == false {
            #expect(FileManager.default.fileExists(atPath: repositoryRoot.appending(path: path).path()))
        }
    }

    let documentURL = repositoryRoot
        .appending(path: manifest.sourceDocument)
    let document = try String(contentsOf: documentURL, encoding: .utf8)
    let documentIDs = professionalAuditRequirementIDs(in: document)

    #expect(Set(manifestIDs) == documentIDs)
    #expect(documentIDs.count == 54)
}

private func taskIDs(in text: String) -> Set<String> {
    let pattern = #"(?m)^id = "(P\d+-T\d+)"$"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return Set(expression.matches(in: text, range: range).compactMap { match in
        guard match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[range])
    })
}

private func repositoryRootURL(filePath: StaticString = #filePath) -> URL {
    var directory = URL(filePath: "\(filePath)").deletingLastPathComponent()
    while directory.lastPathComponent != "HappyPianistAVPTests", directory.pathComponents.count > 1 {
        directory.deleteLastPathComponent()
    }
    return directory.deletingLastPathComponent()
}

private func professionalAuditRequirementIDs(in text: String) -> Set<String> {
    let pattern = #"\b(?:ARCH|SCORE|PERF|NOTATION|OBS|ASSESS|GUIDE|AI|RECORD)-\d{3}\b"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return Set(expression.matches(in: text, range: range).compactMap { match in
        guard let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    })
}
