import Foundation

public enum SongFileStoreError: LocalizedError, Equatable {
    case invalidFileName(String)
    case unreadableScoreFile

    public var errorDescription: String? {
        switch self {
        case .invalidFileName:
            "曲库文件名无效。"
        case .unreadableScoreFile:
            "曲谱文件不可读。"
        }
    }
}

public protocol SongFileStoreProtocol: Actor {
    func scoreFileURL(fileName: String) async throws -> URL
    func audioFileURL(fileName: String) async throws -> URL
    func deleteScoreFile(named fileName: String) async throws
    func deleteAudioFile(named fileName: String) async throws
}

public actor SongFileStore: SongFileStoreProtocol {
    private let fileManager: FileManager
    private let paths: SongLibraryPaths

    public init(
        fileManager: FileManager = .default,
        paths: SongLibraryPaths? = nil
    ) {
        self.fileManager = fileManager
        self.paths = paths ?? SongLibraryPaths(fileManager: fileManager)
    }

    public func scoreFileURL(fileName: String) async throws -> URL {
        let fileURL = try paths.scoresDirectoryURL().appending(path: validatedFileName(fileName))
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              fileManager.isReadableFile(atPath: fileURL.path(percentEncoded: false))
        else {
            throw SongFileStoreError.unreadableScoreFile
        }
        return fileURL
    }

    public func audioFileURL(fileName: String) async throws -> URL {
        try paths.audioDirectoryURL().appending(path: validatedFileName(fileName))
    }

    public func deleteScoreFile(named fileName: String) async throws {
        try removeFileIfExists(
            at: paths.scoresDirectoryURL().appending(path: validatedFileName(fileName))
        )
    }

    public func deleteAudioFile(named fileName: String) async throws {
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
        if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: fileURL)
        }
    }
}
