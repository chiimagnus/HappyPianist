import Foundation

protocol SongLibrarySeederProtocol {
    func seedAndMigrateIfNeeded() throws
}

final class SongLibrarySeeder: SongLibrarySeederProtocol {
    static let seedFileName = "Opus – Ryuichi Sakamoto (Piano Transcription).musicxml"
    static let seedSubdirectory = "Resources/SeedScores"
    private static let legacyImportedScoresDirectoryName = "ImportedScores"

    private let fileManager: FileManager
    private let paths: SongLibraryPaths
    private let indexStore: SongLibraryIndexStoreProtocol
    private let fileStore: SongFileStoreProtocol
    private let bundle: Bundle

    init(
        fileManager: FileManager = .default,
        paths: SongLibraryPaths? = nil,
        indexStore: SongLibraryIndexStoreProtocol? = nil,
        fileStore: SongFileStoreProtocol? = nil,
        bundle: Bundle = Bundle(for: SongLibrarySeeder.self)
    ) {
        let resolvedPaths = paths ?? SongLibraryPaths(fileManager: fileManager)
        self.fileManager = fileManager
        self.paths = resolvedPaths
        self.indexStore = indexStore ?? SongLibraryIndexStore(fileManager: fileManager, paths: resolvedPaths)
        self.fileStore = fileStore ?? SongFileStore(fileManager: fileManager, paths: resolvedPaths)
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
        }
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
        return entry(from: imported)
    }

    private func deleteLegacyImportedScoresDirectoryIfExists() throws {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let legacyDirectoryURL = documentsURL.appendingPathComponent(Self.legacyImportedScoresDirectoryName, isDirectory: true)
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
