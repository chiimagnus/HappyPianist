import Foundation

protocol SongLibrarySeederProtocol {
    func seedAndMigrateIfNeeded() throws
}

final class SongLibrarySeeder: SongLibrarySeederProtocol {
    static let seedFileName = "Opus – Ryuichi Sakamoto (Piano Transcription).musicxml"
    static let seedAudioFileName = "Opus – Ryuichi Sakamoto (Piano Transcription).mp3"
    static let seedSubdirectory = "Resources/SeedScores"
    private static let legacyImportedScoresDirectoryName = "ImportedScores"

    private let fileManager: FileManager
    private let paths: SongLibraryPaths
    private let indexStore: SongLibraryIndexStoreProtocol
    private let fileStore: SongFileStoreProtocol
    private let audioImportService: AudioImportServiceProtocol
    private let bundle: Bundle

    init(
        fileManager: FileManager = .default,
        paths: SongLibraryPaths? = nil,
        indexStore: SongLibraryIndexStoreProtocol? = nil,
        fileStore: SongFileStoreProtocol? = nil,
        audioImportService: AudioImportServiceProtocol? = nil,
        bundle: Bundle = Bundle(for: SongLibrarySeeder.self)
    ) {
        let resolvedPaths = paths ?? SongLibraryPaths(fileManager: fileManager)
        self.fileManager = fileManager
        self.paths = resolvedPaths
        self.indexStore = indexStore ?? SongLibraryIndexStore(fileManager: fileManager, paths: resolvedPaths)
        self.fileStore = fileStore ?? SongFileStore(fileManager: fileManager, paths: resolvedPaths)
        self.audioImportService = audioImportService ?? AudioImportService(
            fileManager: fileManager,
            paths: resolvedPaths
        )
        self.bundle = bundle
    }

    func seedAndMigrateIfNeeded() throws {
        try deleteLegacyImportedScoresDirectoryIfExists()

        var index = try indexStore.load()

        if index.entries.isEmpty {
            if let seedEntry = try seedEntryFromBundle() {
                index.entries.append(seedEntry)
                try indexStore.save(index)
            }
            return
        }

        let seedDisplayName = URL(fileURLWithPath: Self.seedFileName).deletingPathExtension().lastPathComponent
        guard let entryIndex = index.entries.firstIndex(where: { $0.displayName == seedDisplayName }) else { return }
        guard index.entries[entryIndex].audioFileName == nil else { return }
        guard let importedAudioFileName = try importSeedAudioIfAvailable() else { return }

        index.entries[entryIndex].audioFileName = importedAudioFileName
        try indexStore.save(index)
    }

    private func seedEntryFromBundle() throws -> SongLibraryEntry? {
        guard let seedURL = bundle.url(
            forResource: Self.seedFileName,
            withExtension: nil,
            subdirectory: Self.seedSubdirectory
        ) ?? bundle.url(forResource: Self.seedFileName, withExtension: nil) else {
            return nil
        }

        let imported = try fileStore.importMusicXML(from: seedURL)
        var entry = entry(from: imported)
        entry.audioFileName = try importSeedAudioIfAvailable()
        return entry
    }

    private func importSeedAudioIfAvailable() throws -> String? {
        guard let seedURL = bundle.url(
            forResource: Self.seedAudioFileName,
            withExtension: nil,
            subdirectory: Self.seedSubdirectory
        ) ?? bundle.url(forResource: Self.seedAudioFileName, withExtension: nil) else {
            return nil
        }

        return try audioImportService.importAudio(from: seedURL)
    }

    private func deleteLegacyImportedScoresDirectoryIfExists() throws {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let legacyDirectoryURL = documentsURL.appendingPathComponent(
            Self.legacyImportedScoresDirectoryName,
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: legacyDirectoryURL.path()) else {
            return
        }

        try fileManager.removeItem(at: legacyDirectoryURL)
    }

    private func entry(from imported: ImportedSongScoreFile) -> SongLibraryEntry {
        SongLibraryEntry(
            id: UUID(),
            displayName: URL(fileURLWithPath: imported.sourceFileName).deletingPathExtension().lastPathComponent,
            musicXMLFileName: imported.storedFileName,
            importedAt: imported.importedAt,
            audioFileName: nil
        )
    }
}
