import Foundation

public enum SongLibraryPathsError: Error {
    case documentsUnavailable
    case invalidPathComponent
}

public struct SongLibraryPaths {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func rootDirectoryURL() throws -> URL {
        try documentsDirectoryURL().appending(path: SongLibraryLayout.rootDirectoryName, directoryHint: .isDirectory)
    }

    public func scoresDirectoryURL() throws -> URL {
        try rootDirectoryURL().appending(path: SongLibraryLayout.scoresDirectoryName, directoryHint: .isDirectory)
    }

    public func audioDirectoryURL() throws -> URL {
        try rootDirectoryURL().appending(path: SongLibraryLayout.audioDirectoryName, directoryHint: .isDirectory)
    }

    public func indexFileURL() throws -> URL {
        try rootDirectoryURL().appending(path: SongLibraryLayout.indexFileName)
    }

    public func transactionsDirectoryURL() throws -> URL {
        try rootDirectoryURL().appending(
            path: SongLibraryLayout.transactionsDirectoryName,
            directoryHint: .isDirectory
        )
    }

    public func transactionOperationDirectoryURL(operationID: UUID) throws -> URL {
        try transactionsDirectoryURL().appending(
            path: operationID.uuidString.lowercased(),
            directoryHint: .isDirectory
        )
    }

    public func transactionStageFileURL(operationID: UUID, safeFileName: String) throws -> URL {
        try transactionOperationDirectoryURL(operationID: operationID)
            .appending(path: "stage", directoryHint: .isDirectory)
            .appending(path: validatedComponent(safeFileName))
    }

    public func transactionPartialStageFileURL(operationID: UUID) throws -> URL {
        try transactionOperationDirectoryURL(operationID: operationID)
            .appending(path: "stage", directoryHint: .isDirectory)
            .appending(path: ".partial")
    }

    public func transactionBackupFileURL(operationID: UUID, safeFileName: String) throws -> URL {
        try transactionOperationDirectoryURL(operationID: operationID)
            .appending(path: "backup", directoryHint: .isDirectory)
            .appending(path: validatedComponent(safeFileName))
    }

    public func transactionJournalFileURL(operationID: UUID) throws -> URL {
        try transactionOperationDirectoryURL(operationID: operationID)
            .appending(path: "journal.json")
    }

    public func scoreFileURL(safeFileName: String) throws -> URL {
        try scoresDirectoryURL().appending(path: validatedComponent(safeFileName))
    }

    public func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: rootDirectoryURL(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: scoresDirectoryURL(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: audioDirectoryURL(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: transactionsDirectoryURL(), withIntermediateDirectories: true)
    }

    private func validatedComponent(_ component: String) throws -> String {
        guard component.isEmpty == false,
              component != ".",
              component != "..",
              component.contains("/") == false,
              component.contains("\\") == false,
              URL(fileURLWithPath: component).lastPathComponent == component
        else {
            throw SongLibraryPathsError.invalidPathComponent
        }
        return component
    }

    private func documentsDirectoryURL() throws -> URL {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw SongLibraryPathsError.documentsUnavailable
        }
        return documentsURL
    }
}
