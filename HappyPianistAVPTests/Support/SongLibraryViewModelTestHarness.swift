import Foundation
@testable import HappyPianistAVP

@MainActor
enum SongLibraryViewModelTestHarness {
    static func make(
        appState: AppState? = nil,
        index: SongLibraryIndex? = nil,
        indexStore: (any SongLibraryIndexStoreProtocol)? = nil,
        fileStore: (any SongFileStoreProtocol)? = nil,
        bundledEntries: [SongLibraryEntry] = [],
        practicePreparationService: (any PracticePreparationServiceProtocol)? = nil,
        practiceProgressRepository: (any PracticeProgressRepositoryProtocol)? = nil,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        bootstrapLoader: (any SongLibraryBootstrapLoading)? = nil,
        deferInitialLoad: Bool = false
    ) -> SongLibraryViewModel {
        let resolvedAppState = appState ?? AppState()
        let resolvedIndex = index ?? .empty
        let arGuideViewModel = ARGuideViewModel(
            appState: resolvedAppState,
            practiceSetupState: resolvedAppState.practiceSetupState
        )
        return SongLibraryViewModel(
            arGuideViewModel: arGuideViewModel,
            practicePreparationService: practicePreparationService ?? NoopPracticePreparationService(),
            indexStore: indexStore ?? InMemorySongLibraryIndexStore(index: resolvedIndex),
            fileStore: fileStore ?? InMemorySongFileStore(),
            audioImportService: NoopAudioImportService(),
            bundledProvider: StubBundledSongLibraryProvider(entries: bundledEntries),
            audioPlayer: NoopSongAudioPlayer(),
            practiceProgressRepository: practiceProgressRepository ?? InMemoryPracticeProgressRepository(),
            diagnosticsReporter: diagnosticsReporter ?? InMemoryDiagnosticsReporter(),
            bootstrapLoader: bootstrapLoader,
            initialSnapshot: deferInitialLoad
                ? nil
                : .loaded(index: resolvedIndex, bundledEntries: bundledEntries),
            selectionSettleDelay: .zero,
            selectionPersistenceDelay: .zero
        )
    }
}

private actor InMemorySongLibraryIndexStore: SongLibraryIndexStoreProtocol {
    private var index: SongLibraryIndex

    init(index: SongLibraryIndex) {
        self.index = index
    }

    func load() throws -> SongLibraryIndex {
        index
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

private struct InMemorySongFileStore: SongFileStoreProtocol {
    func importMusicXML(from sourceURL: URL) throws -> ImportedSongScoreFile {
        let storedURL = FileManager.default.temporaryDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        return ImportedSongScoreFile(
            sourceFileName: sourceURL.lastPathComponent,
            storedFileName: storedURL.lastPathComponent,
            storedURL: storedURL,
            importedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func scoreFileURL(fileName: String) throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    func audioFileURL(fileName: String) throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    func deleteScoreFile(named _: String) throws {}
    func deleteAudioFile(named _: String) throws {}
}

private struct NoopAudioImportService: AudioImportServiceProtocol {
    func importAudio(from sourceURL: URL) throws -> String {
        sourceURL.lastPathComponent
    }
}

private struct StubBundledSongLibraryProvider: BundledSongLibraryProviderProtocol {
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

private struct NoopPracticePreparationService: PracticePreparationServiceProtocol {
    func prepare(songID _: UUID, from _: URL, file _: ImportedMusicXMLFile) async throws -> PreparedPractice {
        throw NSError(domain: "SongLibraryViewModelTestHarness", code: 1)
    }
}

private final class NoopSongAudioPlayer: SongAudioPlayerProtocol {
    var onPlaybackFinished: ((UUID?) -> Void)?
    private(set) var currentEntryID: UUID?
    var currentTime: TimeInterval { 0 }
    var duration: TimeInterval { 0 }

    init() {}

    func play(entryID: UUID, url _: URL) throws {
        currentEntryID = entryID
    }

    func pause() {}

    func stop() {
        currentEntryID = nil
    }

    func seek(to _: TimeInterval) {}

    func isPlaying(entryID: UUID) -> Bool {
        currentEntryID == entryID
    }
}


private actor InMemoryPracticeProgressRepository: PracticeProgressRepositoryProtocol {
    private var document = PracticeProgressDocument()

    func load() -> PracticeProgressLoadResult { .loaded(document) }
    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        document.songs.first(where: { $0.identity == identity })
    }
    func upsert(_ progress: SongPracticeProgress) {
        document.songs.removeAll(where: { $0.identity == progress.identity })
        document.songs.append(progress)
    }
    func remove(songID: UUID) {
        document.songs.removeAll(where: { $0.identity.songID == songID })
    }
}
