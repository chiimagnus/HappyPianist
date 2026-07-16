import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func songLibraryBootstrapAppliesLoadedSnapshot() async {
    let entry = SongLibraryEntry(
        id: UUID(),
        displayName: "Bundled",
        musicXMLFileName: "Bundled.musicxml",
        scoreFileVersionID: UUID(),
        importedAt: .now,
        audioFileName: nil,
        isBundled: true
    )
    let viewModel = SongLibraryViewModelTestHarness.make(
        bundledEntries: [entry],
        deferInitialLoad: true
    )

    #expect(viewModel.entries.isEmpty)

    await viewModel.loadLibrary()

    #expect(viewModel.entries == [entry])
}

@Test
func liveBootstrapUsesInjectedStoreAndProvider() async {
    let recorder = BootstrapEventRecorder()
    let storedEntry = SongLibraryEntry(
        id: UUID(),
        displayName: "Stored",
        musicXMLFileName: "stored.musicxml",
        scoreFileVersionID: UUID(),
        importedAt: .distantPast,
        audioFileName: nil
    )
    let bundledEntry = SongLibraryEntry(
        id: UUID(),
        displayName: "Bundled",
        musicXMLFileName: "bundled.musicxml",
        scoreFileVersionID: UUID(),
        importedAt: .distantPast,
        audioFileName: nil,
        isBundled: true
    )
    let store = BootstrapRecordingIndexStore(
        index: SongLibraryIndex(entries: [storedEntry], lastSelectedEntryID: storedEntry.id),
        recorder: recorder
    )
    let provider = BootstrapBundledProvider(entries: [bundledEntry])
    let recovery = BootstrapRecordingRecovery(result: .recovered, recorder: recorder)
    let loader = LiveSongLibraryBootstrapLoader(
        transactionRecovery: recovery,
        indexStore: store,
        bundledProvider: provider
    )

    let result = await loader.load()

    #expect(
        result == SongLibraryBootstrapSnapshot(
            index: SongLibraryIndex(entries: [storedEntry], lastSelectedEntryID: storedEntry.id),
            bundledEntries: [bundledEntry]
        )
    )
    #expect(await store.loadCount == 1)
    #expect(recorder.events == ["recover", "load"])
}

@Test
func blockedTransactionRecoveryPreventsIndexSnapshotPublication() async {
    let recorder = BootstrapEventRecorder()
    let store = BootstrapRecordingIndexStore(index: .empty, recorder: recorder)
    let recovery = BootstrapRecordingRecovery(
        result: .blocked(
            SongLibraryBlockedImport(operationID: UUID(), message: "recovery blocked")
        ),
        recorder: recorder
    )
    let loader = LiveSongLibraryBootstrapLoader(
        transactionRecovery: recovery,
        indexStore: store,
        bundledProvider: BootstrapBundledProvider(entries: [])
    )

    let result = await loader.load()

    #expect(result == nil)
    #expect(await store.loadCount == 0)
    #expect(recorder.events == ["recover"])
}

private actor BootstrapRecordingIndexStore: SongLibraryIndexStoreProtocol {
    private var index: SongLibraryIndex
    private let recorder: BootstrapEventRecorder?
    private(set) var loadCount = 0

    init(index: SongLibraryIndex, recorder: BootstrapEventRecorder? = nil) {
        self.index = index
        self.recorder = recorder
    }

    func load() throws -> SongLibraryIndex {
        recorder?.record("load")
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

private actor BootstrapRecordingRecovery: SongLibraryImportTransactionRecovering {
    let result: SongLibraryTransactionRecoveryResult
    let recorder: BootstrapEventRecorder

    init(result: SongLibraryTransactionRecoveryResult, recorder: BootstrapEventRecorder) {
        self.result = result
        self.recorder = recorder
    }

    func recoverPendingTransactions() -> SongLibraryTransactionRecoveryResult {
        recorder.record("recover")
        return result
    }
}

private final class BootstrapEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var events: [String] {
        lock.withLock { storage }
    }

    func record(_ event: String) {
        lock.withLock { storage.append(event) }
    }
}

private struct BootstrapBundledProvider: BundledSongLibraryProviderProtocol {
    let entries: [SongLibraryEntry]

    func bundledEntries() -> [SongLibraryEntry] {
        entries
    }

    func musicXMLURL(fileName _: String) -> URL? {
        nil
    }

    func audioURL(fileName _: String) -> URL? {
        nil
    }
}
