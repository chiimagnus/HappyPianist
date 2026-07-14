import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func rapidSelectionPersistsOnlyTheFinalIntent() async throws {
    let entries = makeSelectionEntries()
    let store = SelectionPersistenceStore(
        index: SongLibraryIndex(entries: entries, lastSelectedEntryID: entries[2].id)
    )
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: entries, lastSelectedEntryID: entries[2].id),
        indexStore: store
    )

    viewModel.selectEntry(entries[0].id)
    viewModel.selectEntry(entries[1].id)
    viewModel.selectEntry(entries[0].id)
    await viewModel.flushPendingSelectionPersistence()

    #expect(viewModel.selectedEntryID == entries[0].id)
    #expect(await store.persistedSelections == [entries[0].id])
    let persistedIndex = try await store.load()
    #expect(persistedIndex.lastSelectedEntryID == entries[0].id)
}

@Test
@MainActor
func selectionChosenDuringOlderMutationStillWinsOnDisk() async throws {
    let entries = makeSelectionEntries()
    let (mutationEntries, mutationEntryContinuation) = AsyncStream<Void>.makeStream()
    var mutationEntryIterator = mutationEntries.makeAsyncIterator()
    let store = SelectionPersistenceStore(
        index: SongLibraryIndex(entries: entries, lastSelectedEntryID: entries[2].id),
        delayFirstSelectionMutation: true,
        onFirstSelectionMutationEntered: { mutationEntryContinuation.yield() }
    )
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: entries, lastSelectedEntryID: entries[2].id),
        indexStore: store
    )

    viewModel.selectEntry(entries[0].id)
    _ = await mutationEntryIterator.next()
    viewModel.selectEntry(entries[1].id)
    await viewModel.flushPendingSelectionPersistence()

    #expect(viewModel.selectedEntryID == entries[1].id)
    #expect(await store.persistedSelections == [entries[0].id, entries[1].id])
    #expect(try await store.load().lastSelectedEntryID == entries[1].id)
}

@Test
@MainActor
func selectionPersistenceFailureKeepsMemorySelectionForRetry() async throws {
    let entries = makeSelectionEntries()
    let store = SelectionPersistenceStore(
        index: SongLibraryIndex(entries: entries, lastSelectedEntryID: entries[2].id),
        failSelectionMutation: true
    )
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: entries, lastSelectedEntryID: entries[2].id),
        indexStore: store
    )

    viewModel.selectEntry(entries[0].id)
    await viewModel.flushPendingSelectionPersistence()

    #expect(viewModel.selectedEntryID == entries[0].id)
    #expect(viewModel.errorMessage?.contains("保存曲库选择失败") == true)
    let persistedIndex = try await store.load()
    #expect(persistedIndex.lastSelectedEntryID == entries[2].id)
}

@Test
@MainActor
func deletingSelectedEntryAdoptsPersistedFallback() async throws {
    let entries = makeSelectionEntries()
    let store = SelectionPersistenceStore(
        index: SongLibraryIndex(entries: entries, lastSelectedEntryID: entries[1].id)
    )
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: entries, lastSelectedEntryID: entries[1].id),
        indexStore: store
    )

    await viewModel.deleteEntry(entryID: entries[1].id)

    #expect(viewModel.selectedEntryID == entries[2].id)
    let persistedIndex = try await store.load()
    #expect(persistedIndex.lastSelectedEntryID == entries[2].id)
}

@Test
@MainActor
func bootstrapRepairsInvalidSelectionAndAcceptsBundledSelection() async throws {
    let userEntry = makeSelectionEntries()[0]
    let bundledEntry = SongLibraryEntry(
        id: UUID(),
        displayName: "Bundled",
        musicXMLFileName: "bundled.musicxml",
        importedAt: .distantPast,
        audioFileName: nil,
        isBundled: true
    )
    let invalidStore = SelectionPersistenceStore(
        index: SongLibraryIndex(entries: [userEntry], lastSelectedEntryID: UUID())
    )
    let invalidIndex = try await invalidStore.load()
    let repaired = SongLibraryViewModelTestHarness.make(
        index: invalidIndex,
        indexStore: invalidStore
    )

    await repaired.flushPendingSelectionPersistence()

    #expect(repaired.selectedEntryID == userEntry.id)
    let repairedIndex = try await invalidStore.load()
    #expect(repairedIndex.lastSelectedEntryID == userEntry.id)

    let bundledStore = SelectionPersistenceStore(
        index: SongLibraryIndex(entries: [], lastSelectedEntryID: bundledEntry.id)
    )
    let bundled = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [], lastSelectedEntryID: bundledEntry.id),
        indexStore: bundledStore,
        bundledEntries: [bundledEntry]
    )

    #expect(bundled.selectedEntryID == bundledEntry.id)
    #expect(await bundledStore.persistedSelections.isEmpty)
}

private func makeSelectionEntries() -> [SongLibraryEntry] {
    ["A", "B", "C"].map { name in
        SongLibraryEntry(
            id: UUID(),
            displayName: name,
            musicXMLFileName: "\(name).musicxml",
            importedAt: .distantPast,
            audioFileName: nil
        )
    }
}

private actor SelectionPersistenceStore: SongLibraryIndexStoreProtocol {
    private var index: SongLibraryIndex
    private var shouldDelayFirstSelectionMutation: Bool
    private let onFirstSelectionMutationEntered: @Sendable () -> Void
    private let failSelectionMutation: Bool
    private(set) var persistedSelections: [UUID?] = []

    init(
        index: SongLibraryIndex,
        delayFirstSelectionMutation: Bool = false,
        onFirstSelectionMutationEntered: @escaping @Sendable () -> Void = {},
        failSelectionMutation: Bool = false
    ) {
        self.index = index
        shouldDelayFirstSelectionMutation = delayFirstSelectionMutation
        self.onFirstSelectionMutationEntered = onFirstSelectionMutationEntered
        self.failSelectionMutation = failSelectionMutation
    }

    func load() throws -> SongLibraryIndex { index }

    func setLastSelectedEntryID(_ entryID: UUID?) throws -> SongLibraryIndex {
        if shouldDelayFirstSelectionMutation {
            shouldDelayFirstSelectionMutation = false
            onFirstSelectionMutationEntered()
            Thread.sleep(forTimeInterval: 0.05)
        }
        if failSelectionMutation {
            throw CocoaError(.fileWriteUnknown)
        }
        index.lastSelectedEntryID = entryID
        persistedSelections.append(entryID)
        return index
    }

    func appendUserEntry(_ entry: SongLibraryEntry) throws -> SongLibraryIndex {
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
        let removedEntry = index.entries.remove(at: entryIndex)
        if index.lastSelectedEntryID == id {
            index.lastSelectedEntryID = fallbackLastSelectedEntryID
        }
        return .applied(index: index, entry: removedEntry)
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
