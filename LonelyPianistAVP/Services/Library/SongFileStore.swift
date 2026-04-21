import Foundation

struct ImportedSongScoreFile: Equatable {
    let sourceFileName: String
    let storedFileName: String
    let storedURL: URL
    let importedAt: Date
}

protocol SongFileStoreProtocol {
    func importMusicXML(from sourceURL: URL) throws -> ImportedSongScoreFile
    func scoreFileURL(fileName: String) throws -> URL
    func audioFileURL(fileName: String) throws -> URL
    func deleteScoreFile(named fileName: String) throws
    func deleteAudioFile(named fileName: String) throws
}

struct SongFileStore: SongFileStoreProtocol {
    private let fileManager: FileManager
    private let paths: SongLibraryPaths
    private let now: () -> Date

    init(
        fileManager: FileManager = .default,
        paths: SongLibraryPaths? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.paths = paths ?? SongLibraryPaths(fileManager: fileManager)
        self.now = now
    }

    func importMusicXML(from sourceURL: URL) throws -> ImportedSongScoreFile {
        let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try paths.ensureDirectoriesExist()

        let importedAt = now()
        let sourceFileName = sourceURL.lastPathComponent
        let targetFileName = makeDestinationFileName(sourceFileName: sourceFileName, importedAt: importedAt)
        let destinationURL = try uniqueScoreDestinationURL(fileName: targetFileName)

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return ImportedSongScoreFile(
            sourceFileName: sourceFileName,
            storedFileName: destinationURL.lastPathComponent,
            storedURL: destinationURL,
            importedAt: importedAt
        )
    }

    func scoreFileURL(fileName: String) throws -> URL {
        try paths.scoresDirectoryURL().appendingPathComponent(safeFileName(fileName))
    }

    func audioFileURL(fileName: String) throws -> URL {
        try paths.audioDirectoryURL().appendingPathComponent(safeFileName(fileName))
    }

    func deleteScoreFile(named fileName: String) throws {
        let targetURL = try scoreFileURL(fileName: fileName)
        try removeFileIfExists(at: targetURL)
    }

    func deleteAudioFile(named fileName: String) throws {
        let targetURL = try audioFileURL(fileName: fileName)
        try removeFileIfExists(at: targetURL)
    }

    private func removeFileIfExists(at fileURL: URL) throws {
        if fileManager.fileExists(atPath: fileURL.path()) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    private func uniqueScoreDestinationURL(fileName: String) throws -> URL {
        let scoresDirectory = try paths.scoresDirectoryURL()
        var candidateURL = scoresDirectory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: candidateURL.path()) == false {
            return candidateURL
        }

        let extensionName = candidateURL.pathExtension
        let baseName = candidateURL.deletingPathExtension().lastPathComponent
        candidateURL = scoresDirectory.appendingPathComponent("\(baseName)-\(UUID().uuidString)")

        if extensionName.isEmpty == false {
            candidateURL.appendPathExtension(extensionName)
        }

        return candidateURL
    }

    private func makeDestinationFileName(sourceFileName: String, importedAt: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: importedAt).replacingOccurrences(of: ":", with: "-")
        return "\(timestamp)-\(safeFileName(sourceFileName))"
    }

    private func safeFileName(_ fileName: String) -> String {
        URL(fileURLWithPath: fileName).lastPathComponent
    }
}
