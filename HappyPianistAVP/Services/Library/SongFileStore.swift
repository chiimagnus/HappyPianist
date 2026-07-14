import Foundation

struct ImportedSongScoreFile: Equatable, Sendable {
    let sourceFileName: String
    let storedFileName: String
    let storedURL: URL
    let importedAt: Date
}

enum SongFileStoreError: LocalizedError, Equatable {
    case invalidFileName(String)
    case unreadableScoreFile

    var errorDescription: String? {
        switch self {
        case .invalidFileName:
            "曲库文件名无效。"
        case .unreadableScoreFile:
            "曲谱文件不可读。"
        }
    }
}

protocol SongFileStoreProtocol: Actor {
    func importMusicXML(from sourceURL: URL) async throws -> ImportedSongScoreFile
    func scoreFileURL(fileName: String) async throws -> URL
    func audioFileURL(fileName: String) async throws -> URL
    func deleteScoreFile(named fileName: String) async throws
    func deleteAudioFile(named fileName: String) async throws
}

actor SongFileStore: SongFileStoreProtocol {
    private let fileManager: FileManager
    private let paths: SongLibraryPaths
    private let now: @Sendable () -> Date

    init(
        fileManager: FileManager = .default,
        paths: SongLibraryPaths? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.paths = paths ?? SongLibraryPaths(fileManager: fileManager)
        self.now = now
    }

    func importMusicXML(from sourceURL: URL) async throws -> ImportedSongScoreFile {
        let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        try paths.ensureDirectoriesExist()
        let importedAt = now()
        let sourceFileName = try validatedFileName(sourceURL.lastPathComponent)
        let targetFileName = makeDestinationFileName(
            sourceFileName: sourceFileName,
            importedAt: importedAt
        )
        let destinationURL = try uniqueScoreDestinationURL(fileName: targetFileName)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return ImportedSongScoreFile(
            sourceFileName: sourceFileName,
            storedFileName: destinationURL.lastPathComponent,
            storedURL: destinationURL,
            importedAt: importedAt
        )
    }

    func scoreFileURL(fileName: String) async throws -> URL {
        let fileURL = try paths.scoresDirectoryURL().appending(path: validatedFileName(fileName))
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path())
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              fileManager.isReadableFile(atPath: fileURL.path())
        else {
            throw SongFileStoreError.unreadableScoreFile
        }
        return fileURL
    }

    func audioFileURL(fileName: String) async throws -> URL {
        try paths.audioDirectoryURL().appending(path: validatedFileName(fileName))
    }

    func deleteScoreFile(named fileName: String) async throws {
        try removeFileIfExists(
            at: paths.scoresDirectoryURL().appending(path: validatedFileName(fileName))
        )
    }

    func deleteAudioFile(named fileName: String) async throws {
        try removeFileIfExists(
            at: paths.audioDirectoryURL().appending(path: validatedFileName(fileName))
        )
    }

    private func validatedFileName(_ fileName: String) throws -> String {
        guard fileName.isEmpty == false,
              fileName != ".",
              fileName != "..",
              URL(fileURLWithPath: fileName).lastPathComponent == fileName,
              fileName.contains("/") == false,
              fileName.contains("\\") == false
        else { throw SongFileStoreError.invalidFileName(fileName) }
        return fileName
    }

    private func removeFileIfExists(at fileURL: URL) throws {
        if fileManager.fileExists(atPath: fileURL.path()) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    private func uniqueScoreDestinationURL(fileName: String) throws -> URL {
        let scoresDirectory = try paths.scoresDirectoryURL()
        var candidateURL = scoresDirectory.appending(path: fileName)
        if fileManager.fileExists(atPath: candidateURL.path()) == false { return candidateURL }
        let extensionName = candidateURL.pathExtension
        let baseName = candidateURL.deletingPathExtension().lastPathComponent
        candidateURL = scoresDirectory.appending(path: "\(baseName)-\(UUID().uuidString)")
        if extensionName.isEmpty == false { candidateURL.appendPathExtension(extensionName) }
        return candidateURL
    }

    private func makeDestinationFileName(sourceFileName: String, importedAt: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: importedAt).replacing(":", with: "-")
        return "\(timestamp)-\(sourceFileName)"
    }
}
