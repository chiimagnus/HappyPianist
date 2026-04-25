import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func songLibraryIndexStoreLoadReturnsEmptyWhenFileMissing() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "SongLibraryIndexStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = SongLibraryPaths(fileManager: fileManager)
    let store = SongLibraryIndexStore(fileManager: fileManager, paths: paths)

    let index = try store.load()
    #expect(index == .empty)
}

@Test
func songLibraryIndexStoreSaveAndLoadRoundTrip() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "SongLibraryIndexStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = SongLibraryPaths(fileManager: fileManager)
    let store = SongLibraryIndexStore(fileManager: fileManager, paths: paths)

    let importedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let entryID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))

    let index = SongLibraryIndex(
        entries: [
            SongLibraryEntry(
                id: entryID,
                displayName: "Opus – Ryuichi Sakamoto (Piano Transcription)",
                musicXMLFileName: "2026-04-21T21-00-00Z-Opus.musicxml",
                importedAt: importedAt,
                audioFileName: "2026-04-21T21-00-00Z-Opus.m4a"
            )
        ],
        lastSelectedEntryID: entryID
    )

    try store.save(index)
    let loaded = try store.load()

    #expect(loaded == index)
}

@Test
func songLibraryIndexStoreLoadReturnsEmptyWhenFileIsEmpty() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "SongLibraryIndexStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = SongLibraryPaths(fileManager: fileManager)
    let store = SongLibraryIndexStore(fileManager: fileManager, paths: paths)

    try paths.ensureDirectoriesExist()
    let indexFileURL = try paths.indexFileURL()
    try Data().write(to: indexFileURL)

    let index = try store.load()
    #expect(index == .empty)
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
