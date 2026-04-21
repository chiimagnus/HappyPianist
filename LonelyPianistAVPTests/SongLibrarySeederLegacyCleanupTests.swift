import Foundation
import Testing
@testable import LonelyPianistAVP

@Test
func songLibrarySeederDeletesLegacyImportedScoresDirectory() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "SongLibrarySeederLegacyCleanup-docs")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let legacyDirectoryURL = documentsURL.appendingPathComponent("ImportedScores", isDirectory: true)
    try FileManager.default.createDirectory(at: legacyDirectoryURL, withIntermediateDirectories: true)
    try Data("legacy".utf8).write(to: legacyDirectoryURL.appendingPathComponent("legacy.musicxml"))

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = SongLibraryPaths(fileManager: fileManager)
    let indexStore = SongLibraryIndexStore(fileManager: fileManager, paths: paths)
    let fileStore = SongFileStore(
        fileManager: fileManager,
        paths: paths,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let seeder = SongLibrarySeeder(
        fileManager: fileManager,
        paths: paths,
        indexStore: indexStore,
        fileStore: fileStore,
        bundle: Bundle(for: SongLibrarySeeder.self)
    )

    try seeder.seedAndMigrateIfNeeded()

    #expect(fileManager.fileExists(atPath: legacyDirectoryURL.path()) == false)
}

private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private final class TestDocumentsFileManager: FileManager {
    private let documentsURL: URL

    init(documentsURL: URL) {
        self.documentsURL = documentsURL
        super.init()
    }

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        if directory == .documentDirectory {
            return [documentsURL]
        }
        return super.urls(for: directory, in: domainMask)
    }
}

