import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func songLibrarySeederSeedsAudioFileForDefaultEntry() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "SongLibrarySeederSeedAudio-docs")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = SongLibraryPaths(fileManager: fileManager)
    let indexStore = SongLibraryIndexStore(fileManager: fileManager, paths: paths)
    let fileStore = SongFileStore(
        fileManager: fileManager,
        paths: paths,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
    let audioImportService = AudioImportService(
        fileManager: fileManager,
        paths: paths,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let seeder = SongLibrarySeeder(
        fileManager: fileManager,
        paths: paths,
        indexStore: indexStore,
        fileStore: fileStore,
        audioImportService: audioImportService,
        bundle: Bundle(for: SongLibrarySeeder.self)
    )

    try seeder.seedAndMigrateIfNeeded()

    let index = try indexStore.load()
    #expect(index.entries.count == 1)

    guard let entry = index.entries.first else { return }
    #expect(entry.audioFileName != nil)

    guard let audioFileName = entry.audioFileName else { return }
    let audioURL = try paths.audioDirectoryURL().appendingPathComponent(audioFileName)
    let data = try Data(contentsOf: audioURL)
    #expect(data.isEmpty == false)
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
