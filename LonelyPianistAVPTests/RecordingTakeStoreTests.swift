import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func takeStoreLoadReturnsEmptyWhenFileMissing() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingTakeStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)

    let takes = try store.load()
    #expect(takes.isEmpty)
}

@Test
func takeStoreSaveAndLoadRoundTrip() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingTakeStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)

    let take = RecordingTake(
        name: "Test Take",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        events: [
            RecordingTakeEvent(time: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
            RecordingTakeEvent(time: 0.5, kind: .noteOff(midi: 60)),
        ]
    )

    try store.save([take])
    let loaded = try store.load()

    #expect(loaded.count == 1)
    #expect(loaded[0].name == "Test Take")
    #expect(loaded[0].events.count == 2)
    #expect(loaded[0].events[0].kind == .noteOn(midi: 60, velocity: 90))
    #expect(loaded[0].events[1].kind == .noteOff(midi: 60))
}

@Test
func takeStoreLoadReturnsEmptyWhenFileIsEmpty() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingTakeStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)

    try paths.ensureDirectoriesExist()
    let takesFileURL = try paths.takesFileURL()
    try Data().write(to: takesFileURL)

    let takes = try store.load()
    #expect(takes.isEmpty)
}

@Test
func takeStoreSaveAndLoadMultipleTakes() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingTakeStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)

    let takes = [
        RecordingTake(name: "Take 1", events: [RecordingTakeEvent(time: 0.0, kind: .noteOn(midi: 60, velocity: 90))]),
        RecordingTake(name: "Take 2", events: [RecordingTakeEvent(time: 0.0, kind: .noteOn(midi: 64, velocity: 80))]),
    ]

    try store.save(takes)
    let loaded = try store.load()

    #expect(loaded.count == 2)
    #expect(loaded[0].name == "Take 1")
    #expect(loaded[1].name == "Take 2")
}

@Test
func takeStoreClearAndReload() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingTakeStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)

    let take = RecordingTake(name: "Test", events: [])
    try store.save([take])
    try store.save([])

    let loaded = try store.load()
    #expect(loaded.isEmpty)
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
