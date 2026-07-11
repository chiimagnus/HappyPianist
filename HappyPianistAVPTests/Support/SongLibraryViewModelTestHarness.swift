import Foundation
@testable import HappyPianistAVP

@MainActor
enum SongLibraryViewModelTestHarness {
    static func make(
        appState: AppState? = nil,
        practiceSetupState: PracticeSetupState? = nil,
        index: SongLibraryIndex? = nil,
        bundledEntries: [SongLibraryEntry] = [],
        practicePreparationService: (any PracticePreparationServiceProtocol)? = nil,
        practiceProgressRepository: (any PracticeProgressRepositoryProtocol)? = nil
    ) -> SongLibraryViewModel {
        let resolvedAppState = appState ?? AppState()
        let resolvedPracticeSetupState = practiceSetupState ?? PracticeSetupState()
        let resolvedIndex = index ?? .empty
        return SongLibraryViewModel(
            appState: resolvedAppState,
            practiceSetupState: resolvedPracticeSetupState,
            practicePreparationService: practicePreparationService ?? NoopPracticePreparationService(),
            indexStore: InMemorySongLibraryIndexStore(index: resolvedIndex),
            fileStore: InMemorySongFileStore(),
            audioImportService: NoopAudioImportService(),
            paths: SongLibraryPaths(),
            bundledProvider: StubBundledSongLibraryProvider(entries: bundledEntries),
            audioPlayer: NoopSongAudioPlayer(),
            practiceProgressRepository: practiceProgressRepository ?? InMemoryPracticeProgressRepository()
        )
    }
}

private final class InMemorySongLibraryIndexStore: SongLibraryIndexStoreProtocol {
    private var index: SongLibraryIndex

    init(index: SongLibraryIndex) {
        self.index = index
    }

    func load() throws -> SongLibraryIndex {
        index
    }

    func save(_ index: SongLibraryIndex) throws {
        self.index = index
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

    init() {}

    func play(entryID: UUID, url _: URL) throws {
        currentEntryID = entryID
    }

    func pause() {}

    func stop() {
        currentEntryID = nil
    }

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
