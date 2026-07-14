import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func libraryKeepsUserEntryThatSharesBundledDisplayName() {
    let sharedName = "Same Title"
    let bundled = SongLibraryEntry(
        id: UUID(),
        displayName: sharedName,
        musicXMLFileName: "bundled.musicxml",
        importedAt: .distantPast,
        audioFileName: nil,
        isBundled: true
    )
    let imported = SongLibraryEntry(
        id: UUID(),
        displayName: sharedName,
        musicXMLFileName: "imported.musicxml",
        importedAt: .now,
        audioFileName: nil
    )
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [imported], lastSelectedEntryID: nil),
        bundledEntries: [bundled]
    )

    #expect(viewModel.entries.map(\.id) == [bundled.id, imported.id])
}

@Test
@MainActor
func libraryDeduplicatesOnlyIdenticalEntryIDs() {
    let id = UUID()
    let bundled = SongLibraryEntry(
        id: id,
        displayName: "Bundled",
        musicXMLFileName: "bundled.musicxml",
        importedAt: .distantPast,
        audioFileName: nil,
        isBundled: true
    )
    let duplicateID = SongLibraryEntry(
        id: id,
        displayName: "Imported",
        musicXMLFileName: "imported.musicxml",
        importedAt: .now,
        audioFileName: nil
    )
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [duplicateID], lastSelectedEntryID: nil),
        bundledEntries: [bundled]
    )

    #expect(viewModel.entries == [bundled])
}

@Test
@MainActor
func batchImportKeepsSuccessfulEntriesVisibleWhenLaterPersistenceFails() async {
    let indexStore = FailingSecondSaveSongLibraryIndexStore()
    let fileStore = RecordingSongFileStore()
    let viewModel = SongLibraryViewModelTestHarness.make(
        indexStore: indexStore,
        fileStore: fileStore
    )

    await viewModel.importMusicXML(from: [
        URL(fileURLWithPath: "/tmp/first.musicxml"),
        URL(fileURLWithPath: "/tmp/second.musicxml"),
    ])
    await viewModel.flushPendingSelectionPersistence()

    #expect(viewModel.index.entries.map(\.displayName) == ["first"])
    #expect(viewModel.selectedEntryID == viewModel.index.entries.first?.id)
    let storedIndex = await indexStore.index
    #expect(storedIndex.entries.map(\.displayName) == ["first"])
    #expect(storedIndex.lastSelectedEntryID == storedIndex.entries.first?.id)
    #expect(fileStore.deletedScoreNames == ["second.musicxml"])
    #expect(viewModel.errorMessage != nil)
}

private actor FailingSecondSaveSongLibraryIndexStore: SongLibraryIndexStoreProtocol {
    private(set) var index = SongLibraryIndex.empty
    private var appendCount = 0

    func load() throws -> SongLibraryIndex { index }

    func setLastSelectedEntryID(_ entryID: UUID?) throws -> SongLibraryIndex {
        index.lastSelectedEntryID = entryID
        return index
    }

    func appendUserEntry(_ entry: SongLibraryEntry) throws -> SongLibraryIndex {
        appendCount += 1
        guard appendCount == 1 else { throw CocoaError(.fileWriteUnknown) }
        index.entries.append(entry)
        return index
    }

    func removeUserEntry(
        id: UUID,
        fallbackLastSelectedEntryID: UUID?
    ) throws -> SongLibraryEntryMutationResult {
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == id }) else {
            return .notFound(index: index)
        }
        let entry = index.entries.remove(at: entryIndex)
        if index.lastSelectedEntryID == id {
            index.lastSelectedEntryID = fallbackLastSelectedEntryID
        }
        return .applied(index: index, entry: entry)
    }

    func updateAudioFileName(
        entryID: UUID,
        expectedCurrentFileName: String?,
        newFileName: String?
    ) throws -> SongLibraryEntryMutationResult {
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == entryID }) else {
            return .notFound(index: index)
        }
        guard index.entries[entryIndex].audioFileName == expectedCurrentFileName else {
            return .conflict(index: index, entry: index.entries[entryIndex])
        }
        index.entries[entryIndex].audioFileName = newFileName
        return .applied(index: index, entry: index.entries[entryIndex])
    }
}

private final class RecordingSongFileStore: SongFileStoreProtocol {
    private(set) var deletedScoreNames: [String] = []

    func importMusicXML(from sourceURL: URL) throws -> ImportedSongScoreFile {
        ImportedSongScoreFile(
            sourceFileName: sourceURL.lastPathComponent,
            storedFileName: sourceURL.lastPathComponent,
            storedURL: sourceURL,
            importedAt: .distantPast
        )
    }

    func scoreFileURL(fileName: String) throws -> URL { URL(fileURLWithPath: "/tmp/\(fileName)") }
    func audioFileURL(fileName: String) throws -> URL { URL(fileURLWithPath: "/tmp/\(fileName)") }
    func deleteScoreFile(named fileName: String) throws { deletedScoreNames.append(fileName) }
    func deleteAudioFile(named _: String) throws {}
}
