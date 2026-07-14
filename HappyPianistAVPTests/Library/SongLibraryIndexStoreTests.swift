import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func songLibraryIndexStoreReturnsEmptyOnlyForMissingOrBlankFile() async throws {
    let fixture = try SongLibraryIndexStoreFixture()
    defer { fixture.remove() }

    #expect(try await fixture.store.load() == .empty)

    try FileManager.default.createDirectory(
        at: fixture.indexFileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let indexFileURL = fixture.indexFileURL
    try Data(" \n\t".utf8).write(to: indexFileURL)
    #expect(try await fixture.store.load() == .empty)
}

@Test
func songLibraryIndexMutationsPreserveUnrelatedConcerns() async throws {
    let fixture = try SongLibraryIndexStoreFixture()
    defer { fixture.remove() }
    let first = makeEntry(name: "first")
    let second = makeEntry(name: "second")

    let store = fixture.store
    _ = try await store.appendUserEntry(first)
    async let selected = store.setLastSelectedEntryID(first.id)
    async let appended = store.appendUserEntry(second)
    _ = try await (selected, appended)
    let afterAppend = try await store.load()

    #expect(afterAppend.entries == [first, second])
    #expect(afterAppend.lastSelectedEntryID == first.id)

    async let reselection = store.setLastSelectedEntryID(second.id)
    async let audioUpdate = store.updateAudioFileName(
        entryID: first.id,
        expectedCurrentFileName: nil,
        newFileName: "first.mp3"
    )
    _ = try await (reselection, audioUpdate)
    let final = try await store.load()

    #expect(final.lastSelectedEntryID == second.id)
    #expect(final.entries.first?.audioFileName == "first.mp3")
}

@Test
func songLibraryIndexRemoveReturnsPersistedEntryAndKeepsOrder() async throws {
    let fixture = try SongLibraryIndexStoreFixture()
    defer { fixture.remove() }
    let first = makeEntry(name: "first")
    let second = makeEntry(name: "second")
    let third = makeEntry(name: "third")
    _ = try await fixture.store.appendUserEntry(first)
    _ = try await fixture.store.appendUserEntry(second)
    _ = try await fixture.store.appendUserEntry(third)
    _ = try await fixture.store.setLastSelectedEntryID(second.id)

    let result = try await fixture.store.removeUserEntry(
        id: second.id,
        fallbackLastSelectedEntryID: third.id
    )
    guard case let .applied(index, removedEntry) = result else {
        Issue.record("Expected applied removal")
        return
    }

    #expect(removedEntry == second)
    #expect(index.entries == [first, third])
    #expect(index.lastSelectedEntryID == third.id)
}

@Test
func songLibraryIndexAudioUpdateRejectsStaleExpectation() async throws {
    let fixture = try SongLibraryIndexStoreFixture()
    defer { fixture.remove() }
    var entry = makeEntry(name: "song")
    entry.audioFileName = "current.mp3"
    _ = try await fixture.store.appendUserEntry(entry)

    let result = try await fixture.store.updateAudioFileName(
        entryID: entry.id,
        expectedCurrentFileName: nil,
        newFileName: "replacement.mp3"
    )

    guard case let .conflict(index, actualEntry) = result else {
        Issue.record("Expected conflict")
        return
    }
    #expect(actualEntry.audioFileName == "current.mp3")
    #expect(index.entries == [entry])
    #expect(try await fixture.store.load() == index)
}

@Test
func songLibraryIndexAcceptsBundledSelectionID() async throws {
    let fixture = try SongLibraryIndexStoreFixture()
    defer { fixture.remove() }
    let bundledID = UUID()

    let index = try await fixture.store.setLastSelectedEntryID(bundledID)

    #expect(index.entries.isEmpty)
    #expect(index.lastSelectedEntryID == bundledID)
}

@Test
func corruptedSongLibraryIndexIsPreservedAndBlocksEveryMutation() async throws {
    let fixture = try SongLibraryIndexStoreFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
        at: fixture.indexFileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let indexFileURL = fixture.indexFileURL
    let corruptedData = Data("not-json".utf8)
    try corruptedData.write(to: indexFileURL)
    let entry = makeEntry(name: "blocked")

    await #expect(throws: SongLibraryIndexStoreError.corrupted) {
        _ = try await fixture.store.load()
    }
    await #expect(throws: SongLibraryIndexStoreError.corrupted) {
        _ = try await fixture.store.setLastSelectedEntryID(UUID())
    }
    await #expect(throws: SongLibraryIndexStoreError.corrupted) {
        _ = try await fixture.store.appendUserEntry(entry)
    }
    await #expect(throws: SongLibraryIndexStoreError.corrupted) {
        _ = try await fixture.store.removeUserEntry(
            id: entry.id,
            fallbackLastSelectedEntryID: nil
        )
    }
    await #expect(throws: SongLibraryIndexStoreError.corrupted) {
        _ = try await fixture.store.updateAudioFileName(
            entryID: entry.id,
            expectedCurrentFileName: nil,
            newFileName: "blocked.mp3"
        )
    }

    #expect(try Data(contentsOf: indexFileURL) == corruptedData)
}

private func makeEntry(name: String) -> SongLibraryEntry {
    SongLibraryEntry(
        id: UUID(),
        displayName: name,
        musicXMLFileName: "\(name).musicxml",
        importedAt: Date(timeIntervalSince1970: 1_700_000_000),
        audioFileName: nil
    )
}

private struct SongLibraryIndexStoreFixture {
    let documentsURL: URL
    let indexFileURL: URL
    let store: SongLibraryIndexStore

    init() throws {
        documentsURL = FileManager.default.temporaryDirectory
            .appending(path: "SongLibraryIndexStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: documentsURL,
            withIntermediateDirectories: true
        )
        indexFileURL = documentsURL
            .appending(path: SongLibraryLayout.rootDirectoryName, directoryHint: .isDirectory)
            .appending(path: SongLibraryLayout.indexFileName)
        let fileManager: FileManager = TestDocumentsFileManager(documentsURL: documentsURL)
        let paths = SongLibraryPaths(fileManager: fileManager)
        store = SongLibraryIndexStore(fileManager: fileManager, paths: paths)
    }

    func remove() {
        try? FileManager.default.removeItem(at: documentsURL)
    }
}

private final class TestDocumentsFileManager: FileManager {
    private let documentsURL: URL

    init(documentsURL: URL) {
        self.documentsURL = documentsURL
        super.init()
    }

    override func urls(
        for directory: SearchPathDirectory,
        in domainMask: SearchPathDomainMask
    ) -> [URL] {
        if directory == .documentDirectory {
            return [documentsURL]
        }
        return super.urls(for: directory, in: domainMask)
    }
}
