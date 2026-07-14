import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func songLibraryIndexStoreReturnsEmptyOnlyForMissingFile() async throws {
    let fixture = try SongLibraryIndexStoreFixture()
    defer { fixture.remove() }

    #expect(try await fixture.store.load() == .empty)

    try FileManager.default.createDirectory(
        at: fixture.indexFileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let indexFileURL = fixture.indexFileURL
    try Data(" \n\t".utf8).write(to: indexFileURL)
    await #expect(throws: SongLibraryIndexStoreError.corrupted) {
        _ = try await fixture.store.load()
    }
}

@Test
func songLibraryIndexStoreDecodesLegacyEntryWithoutVersionToken() async throws {
    let fixture = try SongLibraryIndexStoreFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
        at: fixture.indexFileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let id = UUID()
    let json = """
    {
      "entries": [{
        "id": "\(id.uuidString)",
        "displayName": "Legacy",
        "musicXMLFileName": "legacy.musicxml",
        "importedAt": "2024-01-01T00:00:00Z",
        "audioFileName": null
      }],
      "lastSelectedEntryID": "\(id.uuidString)"
    }
    """
    try Data(json.utf8).write(to: fixture.indexFileURL)

    let index = try await fixture.store.load()

    #expect(index.entries.first?.scoreFileVersionID == nil)
    #expect(index.lastSelectedEntryID == id)
}

@Test
func songLibraryEntryVersionTokenRoundTrips() throws {
    let token = UUID()
    let entry = SongLibraryEntry(
        id: UUID(),
        displayName: "Versioned",
        musicXMLFileName: "versioned.musicxml",
        scoreFileVersionID: token,
        importedAt: Date(timeIntervalSince1970: 100),
        audioFileName: nil
    )
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    #expect(try decoder.decode(SongLibraryEntry.self, from: encoder.encode(entry)) == entry)
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
func songLibraryScoreReplacementPreservesEntryAndIndexConcerns() async throws {
    let fixture = try SongLibraryIndexStoreFixture()
    defer { fixture.remove() }
    let first = makeEntry(name: "first")
    var replaced = makeEntry(name: "replaced")
    replaced.scoreFileVersionID = UUID()
    replaced.audioFileName = "replaced.m4a"
    let third = makeEntry(name: "third")
    _ = try await fixture.store.appendUserEntry(first)
    _ = try await fixture.store.appendUserEntry(replaced)
    _ = try await fixture.store.appendUserEntry(third)
    _ = try await fixture.store.setLastSelectedEntryID(replaced.id)
    let newToken = UUID()
    let newDate = Date(timeIntervalSince1970: 1_800_000_000)

    let result = try await fixture.store.replaceUserScore(
        expectedSongID: replaced.id,
        expectedScoreFileVersionID: replaced.scoreFileVersionID,
        expectedMusicXMLFileName: replaced.musicXMLFileName,
        with: SongLibraryScoreReplacement(
            musicXMLFileName: "replacement.musicxml",
            importedAt: newDate,
            scoreFileVersionID: newToken
        )
    )

    guard case let .applied(index, updated) = result else {
        Issue.record("Expected applied replacement")
        return
    }
    #expect(index.entries.map(\.id) == [first.id, replaced.id, third.id])
    #expect(index.lastSelectedEntryID == replaced.id)
    #expect(updated.displayName == replaced.displayName)
    #expect(updated.audioFileName == "replaced.m4a")
    #expect(updated.isBundled == replaced.isBundled)
    #expect(updated.musicXMLFileName == "replacement.musicxml")
    #expect(updated.importedAt == newDate)
    #expect(updated.scoreFileVersionID == newToken)
}

@Test
func songLibraryScoreReplacementRejectsStaleOrAmbiguousExpectationWithoutWriting() async throws {
    let fixture = try SongLibraryIndexStoreFixture()
    defer { fixture.remove() }
    var entry = makeEntry(name: "song")
    entry.scoreFileVersionID = UUID()
    _ = try await fixture.store.appendUserEntry(entry)
    _ = try await fixture.store.appendUserEntry(entry)
    let before = try await fixture.store.load()

    let result = try await fixture.store.replaceUserScore(
        expectedSongID: entry.id,
        expectedScoreFileVersionID: entry.scoreFileVersionID,
        expectedMusicXMLFileName: entry.musicXMLFileName,
        with: SongLibraryScoreReplacement(
            musicXMLFileName: "replacement.musicxml",
            importedAt: .now,
            scoreFileVersionID: UUID()
        )
    )

    guard case let .conflict(index, matchingEntries) = result else {
        Issue.record("Expected replacement conflict")
        return
    }
    #expect(matchingEntries.count == 2)
    #expect(index == before)
    #expect(try await fixture.store.load() == before)
}

@Test
func songLibraryScoreReplacementRequiresByteExactUnicodeFileName() async throws {
    let fixture = try SongLibraryIndexStoreFixture()
    defer { fixture.remove() }
    var entry = makeEntry(name: "unicode")
    entry.musicXMLFileName = "Cafe\u{301}.musicxml"
    entry.scoreFileVersionID = UUID()
    _ = try await fixture.store.appendUserEntry(entry)

    let result = try await fixture.store.replaceUserScore(
        expectedSongID: entry.id,
        expectedScoreFileVersionID: entry.scoreFileVersionID,
        expectedMusicXMLFileName: "Café.musicxml",
        with: SongLibraryScoreReplacement(
            musicXMLFileName: "replacement.musicxml",
            importedAt: .now,
            scoreFileVersionID: UUID()
        )
    )

    guard case .conflict = result else {
        Issue.record("Expected byte-exact filename conflict")
        return
    }
    #expect(try await fixture.store.load().entries == [entry])
}

@Test
func songLibraryScoreReplacementSerializesWithSelectionAndAudioMutations() async throws {
    let fixture = try SongLibraryIndexStoreFixture()
    defer { fixture.remove() }
    var entry = makeEntry(name: "song")
    entry.scoreFileVersionID = UUID()
    let other = makeEntry(name: "other")
    _ = try await fixture.store.appendUserEntry(entry)
    _ = try await fixture.store.appendUserEntry(other)
    let newToken = UUID()
    let entryID = entry.id
    let expectedToken = entry.scoreFileVersionID
    let expectedFileName = entry.musicXMLFileName
    let otherID = other.id

    async let replacement = fixture.store.replaceUserScore(
        expectedSongID: entryID,
        expectedScoreFileVersionID: expectedToken,
        expectedMusicXMLFileName: expectedFileName,
        with: SongLibraryScoreReplacement(
            musicXMLFileName: "replacement.musicxml",
            importedAt: .now,
            scoreFileVersionID: newToken
        )
    )
    async let selection = fixture.store.setLastSelectedEntryID(otherID)
    async let audio = fixture.store.updateAudioFileName(
        entryID: entryID,
        expectedCurrentFileName: nil,
        newFileName: "song.mp3"
    )
    _ = try await (replacement, selection, audio)

    let final = try await fixture.store.load()
    #expect(final.lastSelectedEntryID == otherID)
    #expect(final.entries.first?.musicXMLFileName == "replacement.musicxml")
    #expect(final.entries.first?.scoreFileVersionID == newToken)
    #expect(final.entries.first?.audioFileName == "song.mp3")
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
        _ = try await fixture.store.replaceUserScore(
            expectedSongID: entry.id,
            expectedScoreFileVersionID: nil,
            expectedMusicXMLFileName: entry.musicXMLFileName,
            with: SongLibraryScoreReplacement(
                musicXMLFileName: "blocked.musicxml",
                importedAt: .now,
                scoreFileVersionID: UUID()
            )
        )
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

@Test
func symbolicLinkIndexIsPreservedAndBlocksLoadAndMutation() async throws {
    let fixture = try SongLibraryIndexStoreFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
        at: fixture.indexFileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let externalURL = fixture.documentsURL.appending(path: "external-index.json")
    let externalData = try JSONEncoder().encode(SongLibraryIndex.empty)
    try externalData.write(to: externalURL)
    try FileManager.default.createSymbolicLink(
        at: fixture.indexFileURL,
        withDestinationURL: externalURL
    )

    await #expect(throws: SongLibraryIndexStoreError.corrupted) {
        _ = try await fixture.store.load()
    }
    await #expect(throws: SongLibraryIndexStoreError.corrupted) {
        _ = try await fixture.store.appendUserEntry(makeEntry(name: "blocked"))
    }
    #expect(try fixture.indexFileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    #expect(try Data(contentsOf: externalURL) == externalData)
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
