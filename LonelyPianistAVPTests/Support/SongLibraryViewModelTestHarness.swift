import Foundation
@testable import LonelyPianistAVP

@MainActor
enum SongLibraryViewModelTestHarness {
    static func make(
        appState: AppState? = nil,
        practiceSetupState: PracticeSetupState? = nil,
        index: SongLibraryIndex? = nil,
        bundledEntries: [SongLibraryEntry] = []
    ) -> SongLibraryViewModel {
        let resolvedAppState = appState ?? AppState()
        let resolvedPracticeSetupState = practiceSetupState ?? PracticeSetupState()
        let resolvedIndex = index ?? .empty
        return SongLibraryViewModel(
            appState: resolvedAppState,
            practiceSetupState: resolvedPracticeSetupState,
            practicePreparationService: NoopPracticePreparationService(),
            indexStore: InMemorySongLibraryIndexStore(index: resolvedIndex),
            fileStore: InMemorySongFileStore(),
            audioImportService: NoopAudioImportService(),
            paths: SongLibraryPaths(),
            bundledProvider: StubBundledSongLibraryProvider(entries: bundledEntries),
            audioPlayer: NoopSongAudioPlayer()
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

    init(entries: [SongLibraryEntry]) {
        self.entries = entries
    }

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
    func prepare(from _: URL, file _: ImportedMusicXMLFile) throws -> PreparedPractice {
        throw NSError(domain: "SongLibraryViewModelTestHarness", code: 1)
    }
}

private final class NoopSongAudioPlayer: SongAudioPlayerProtocol {
    var onPlaybackFinished: ((UUID?) -> Void)?
    private(set) var currentEntryID: UUID?

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
