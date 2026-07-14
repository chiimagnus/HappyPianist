import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func songLibraryBootstrapLoadsOnceWithoutBlockingViewModelConstruction() async {
    let entry = SongLibraryEntry(
        id: UUID(),
        displayName: "Bundled",
        musicXMLFileName: "Bundled.musicxml",
        importedAt: .now,
        audioFileName: nil,
        isBundled: true
    )
    let loader = TestSongLibraryBootstrapLoader(
        snapshot: .loaded(index: .empty, bundledEntries: [entry])
    )
    let viewModel = SongLibraryViewModelTestHarness.make(
        bootstrapLoader: loader,
        deferInitialLoad: true
    )

    #expect(viewModel.hasLoadedLibrary == false)
    #expect(viewModel.entries.isEmpty)

    await viewModel.loadLibraryIfNeeded()
    await viewModel.loadLibraryIfNeeded()

    #expect(viewModel.hasLoadedLibrary)
    #expect(viewModel.entries == [entry])
    #expect(await loader.loadCount() == 1)
}

@MainActor
@Test
func blockedBootstrapPreservesMemoryAndCanRetry() async {
    let existing = SongLibraryEntry(
        id: UUID(),
        displayName: "Existing",
        musicXMLFileName: "existing.musicxml",
        importedAt: .distantPast,
        audioFileName: nil
    )
    let recovered = SongLibraryEntry(
        id: UUID(),
        displayName: "Recovered",
        musicXMLFileName: "recovered.musicxml",
        importedAt: .now,
        audioFileName: nil
    )
    let loader = SequencedSongLibraryBootstrapLoader(
        snapshots: [
            .blocked(failure: SongLibraryBootstrapFailure(message: "index corrupted")),
            .loaded(index: SongLibraryIndex(entries: [recovered], lastSelectedEntryID: nil), bundledEntries: []),
        ]
    )
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [existing], lastSelectedEntryID: existing.id),
        bootstrapLoader: loader,
        deferInitialLoad: true
    )
    viewModel.index = SongLibraryIndex(entries: [existing], lastSelectedEntryID: existing.id)

    await viewModel.loadLibraryIfNeeded()

    #expect(viewModel.hasLoadedLibrary == false)
    #expect(viewModel.isLibraryLoading == false)
    #expect(viewModel.index.entries == [existing])
    #expect(viewModel.bootstrapFailureMessage == "index corrupted")

    await viewModel.loadLibraryIfNeeded()

    #expect(viewModel.hasLoadedLibrary)
    #expect(viewModel.index.entries == [recovered])
    #expect(viewModel.bootstrapFailureMessage == nil)
}

@Test
func liveBootstrapUsesInjectedStoreAndProvider() async {
    let storedEntry = SongLibraryEntry(
        id: UUID(),
        displayName: "Stored",
        musicXMLFileName: "stored.musicxml",
        importedAt: .distantPast,
        audioFileName: nil
    )
    let bundledEntry = SongLibraryEntry(
        id: UUID(),
        displayName: "Bundled",
        musicXMLFileName: "bundled.musicxml",
        importedAt: .distantPast,
        audioFileName: nil,
        isBundled: true
    )
    let store = BootstrapRecordingIndexStore(
        index: SongLibraryIndex(entries: [storedEntry], lastSelectedEntryID: storedEntry.id)
    )
    let provider = BootstrapBundledProvider(entries: [bundledEntry])
    let loader = LiveSongLibraryBootstrapLoader(indexStore: store, bundledProvider: provider)

    let result = await loader.load()

    #expect(
        result == .loaded(
            index: SongLibraryIndex(entries: [storedEntry], lastSelectedEntryID: storedEntry.id),
            bundledEntries: [bundledEntry]
        )
    )
    #expect(await store.loadCount == 1)
}

private actor TestSongLibraryBootstrapLoader: SongLibraryBootstrapLoading {
    private let snapshot: SongLibraryBootstrapSnapshot
    private var count = 0

    init(snapshot: SongLibraryBootstrapSnapshot) {
        self.snapshot = snapshot
    }

    func load() -> SongLibraryBootstrapSnapshot {
        count += 1
        return snapshot
    }

    func loadCount() -> Int {
        count
    }
}

private actor SequencedSongLibraryBootstrapLoader: SongLibraryBootstrapLoading {
    private var snapshots: [SongLibraryBootstrapSnapshot]

    init(snapshots: [SongLibraryBootstrapSnapshot]) {
        self.snapshots = snapshots
    }

    func load() -> SongLibraryBootstrapSnapshot {
        snapshots.removeFirst()
    }
}

private actor BootstrapRecordingIndexStore: SongLibraryIndexStoreProtocol {
    private var index: SongLibraryIndex
    private(set) var loadCount = 0

    init(index: SongLibraryIndex) {
        self.index = index
    }

    func load() throws -> SongLibraryIndex {
        loadCount += 1
        return index
    }

    func setLastSelectedEntryID(_ entryID: UUID?) throws -> SongLibraryIndex {
        index.lastSelectedEntryID = entryID
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

private struct BootstrapBundledProvider: BundledSongLibraryProviderProtocol {
    let entries: [SongLibraryEntry]

    func bundledEntries() -> [SongLibraryEntry] { entries }
    func musicXMLURL(fileName _: String) -> URL? { nil }
    func audioURL(fileName _: String) -> URL? { nil }
}
