import Foundation

protocol SongLibrarySeederProtocol {
    func seedAndMigrateIfNeeded() throws
}

final class SongLibrarySeeder: SongLibrarySeederProtocol {
    static let seedFileName = "Opus – Ryuichi Sakamoto (Piano Transcription).musicxml"
    static let seedSubdirectory = "Resources/SeedScores"

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
        var index = try indexStore.load()
        var didMutate = false

        if index.entries.isEmpty {
            let migratedEntries = try migrateLegacyImportedScores()
            if migratedEntries.isEmpty == false {
                index.entries.append(contentsOf: migratedEntries)
                didMutate = true
            }
        }

        if index.entries.isEmpty {
            if let seedEntry = try seedEntryFromBundle() {
                index.entries.append(seedEntry)
                didMutate = true
            }
        }

        if didMutate {
            try indexStore.save(index)
        }
    }

    private func migrateLegacyImportedScores() throws -> [SongLibraryEntry] {
        let legacyDirectoryURL = try paths.legacyImportedScoresDirectoryURL()
        guard fileManager.fileExists(atPath: legacyDirectoryURL.path()) else {
            return []
        }

        let legacyURLs = try fileManager.contentsOfDirectory(
            at: legacyDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var migratedEntries: [SongLibraryEntry] = []

        for legacyURL in legacyURLs {
            let values = try legacyURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }

            let ext = legacyURL.pathExtension.lowercased()
            guard ext == "xml" || ext == "musicxml" else {
                continue
            }

            let imported = try fileStore.importMusicXML(from: legacyURL)
            migratedEntries.append(entry(from: imported))
        }

        return migratedEntries
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
