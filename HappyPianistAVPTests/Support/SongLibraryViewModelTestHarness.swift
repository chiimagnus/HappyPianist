import Foundation
@testable import HappyPianistAVP

@MainActor
enum SongLibraryViewModelTestHarness {
    static func make(
        index: SongLibraryIndex? = nil,
        indexStore: (any SongLibraryIndexStoreProtocol)? = nil,
        importTransactionService: (any SongLibraryImportTransactionServicing)? = nil,
        fileStore: (any SongFileStoreProtocol)? = nil,
        bundledEntries: [SongLibraryEntry] = [],
        practiceProgressRepository: (any PracticeProgressRepositoryProtocol)? = nil,
        practiceProgressRecovery: (any PracticeProgressRecoveryProtocol)? = nil,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        snapshotBuilder: (any SongPracticeLibrarySnapshotBuilding)? = nil,
        snapshotSleeper: (any SleeperProtocol)? = nil,
        snapshotSettleDelay: Duration = .zero,
        audioPlayer: (any SongAudioPlayerProtocol)? = nil,
        bootstrapLoader: (any SongLibraryBootstrapLoading)? = nil,
        deferInitialLoad: Bool = false
    ) -> SongLibraryViewModel {
        let resolvedIndex = index ?? .empty
        let resolvedIndexStore = indexStore ?? InMemorySongLibraryIndexStore(index: resolvedIndex)
        let resolvedFileStore = fileStore ?? InMemorySongFileStore()
        let resolvedBundledProvider = StubBundledSongLibraryProvider(entries: bundledEntries)
        let resolvedBootstrapLoader = bootstrapLoader ?? FixedSongLibraryBootstrapLoader(
            snapshot: SongLibraryBootstrapSnapshot(index: resolvedIndex, bundledEntries: bundledEntries)
        )
        return SongLibraryViewModel(
            indexStore: resolvedIndexStore,
            importTransactionService: importTransactionService ?? NoopSongLibraryImportTransactionService(),
            fileStore: resolvedFileStore,
            audioImportService: NoopAudioImportService(),
            bundledProvider: resolvedBundledProvider,
            audioPlayer: audioPlayer ?? NoopSongAudioPlayer(),
            practiceProgressRepository: practiceProgressRepository ?? InMemoryPracticeProgressRepository(),
            practiceProgressRecovery: practiceProgressRecovery,
            diagnosticsReporter: diagnosticsReporter ?? NoopLibraryDiagnosticsReporter(),
            snapshotBuilder: snapshotBuilder ?? SongPracticeLibrarySnapshotBuilder(),
            bootstrapLoader: resolvedBootstrapLoader,
            initialSnapshot: deferInitialLoad
                ? nil
                : SongLibraryBootstrapSnapshot(index: resolvedIndex, bundledEntries: bundledEntries),
            snapshotSleeper: snapshotSleeper ?? TaskSleeper(),
            snapshotSettleDelay: snapshotSettleDelay,
            selectionPersistenceDelay: .zero
        )
    }
}

private actor FixedSongLibraryBootstrapLoader: SongLibraryBootstrapLoading {
    let snapshot: SongLibraryBootstrapSnapshot

    init(snapshot: SongLibraryBootstrapSnapshot) {
        self.snapshot = snapshot
    }

    func load() -> SongLibraryBootstrapSnapshot? {
        snapshot
    }
}

private actor NoopLibraryDiagnosticsReporter: DiagnosticsReporting {
    func record(_: DiagnosticEvent) -> DiagnosticRecordResult {
        DiagnosticRecordResult(persistedForExport: false)
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

private actor InMemorySongFileStore: SongFileStoreProtocol {
    func scoreFileURL(fileName: String) async throws -> URL {
        FileManager.default.temporaryDirectory.appending(path: fileName)
    }

    func audioFileURL(fileName: String) async throws -> URL {
        FileManager.default.temporaryDirectory.appending(path: fileName)
    }

    func deleteScoreFile(named _: String) async throws {}
    func deleteAudioFile(named _: String) async throws {}
}

private actor NoopSongLibraryImportTransactionService: SongLibraryImportTransactionServicing {
    func recoverPendingTransactions() -> SongLibraryTransactionRecoveryResult {
        .recovered
    }

    func stageImports(from selectedURLs: [URL]) -> SongLibraryImportBatchStageResult {
        SongLibraryImportBatchStageResult(
            items: selectedURLs.map {
                .failure(
                    SongLibraryImportItemFailure(
                        fileName: $0.lastPathComponent,
                        message: "测试未配置导入事务"
                    )
                )
            },
            blocked: nil
        )
    }

    func process(operationID: UUID) -> SongLibraryImportProcessResult {
        .blocked(SongLibraryBlockedImport(operationID: operationID, message: "测试未配置导入事务"))
    }

    func confirm(operationID: UUID) -> SongLibraryImportProcessResult {
        .blocked(SongLibraryBlockedImport(operationID: operationID, message: "测试未配置导入事务"))
    }

    func cancel(operationID _: UUID) -> Bool {
        true
    }
}

private actor NoopAudioImportService: AudioImportServiceProtocol {
    func importAudio(from sourceURL: URL) async throws -> String {
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

private final class NoopSongAudioPlayer: SongAudioPlayerProtocol {
    var onPlaybackFinished: ((UUID?) -> Void)?
    private(set) var currentEntryID: UUID?
    var currentTime: TimeInterval {
        0
    }

    var duration: TimeInterval {
        0
    }

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

private actor InMemoryPracticeProgressRepository:
    PracticeProgressRepositoryProtocol,
    PracticeSessionRepositoryProtocol
{
    private var document = PracticeProgressDocument()

    func load() -> PracticeProgressLoadResult {
        .loaded(document)
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        PracticeProgressRecordOrder.preferred(
            in: document.songs.filter { $0.identity == identity }
        )
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(
            songID: songID,
            progresses: document.songs.filter { $0.identity.songID == songID },
            scoreMetadata: document.scoreMetadata.filter { $0.songID == songID },
            sessions: document.sessions.filter { $0.songID == songID }
        ))
    }

    func upsert(_ progress: SongPracticeProgress) {
        document.songs.removeAll(where: { $0.identity == progress.identity })
        document.songs.append(progress)
    }

    func upsert(_ metadata: SongScorePracticeMetadata) {
        document.scoreMetadata.removeAll {
            $0.songID == metadata.songID
                && $0.scoreFileVersionID == metadata.scoreFileVersionID
                && $0.scoreRevision == metadata.scoreRevision
        }
        document.scoreMetadata.append(metadata)
    }

    func upsert(_ session: PracticeSessionRecord) {
        document.sessions.removeAll(where: { $0.id == session.id })
        document.sessions.append(session)
    }

    func abandonLiveSession(id _: UUID) {}
    func remove(songID: UUID) {
        document.songs.removeAll(where: { $0.identity.songID == songID })
        document.scoreMetadata.removeAll(where: { $0.songID == songID })
        document.sessions.removeAll(where: { $0.songID == songID })
    }
}
