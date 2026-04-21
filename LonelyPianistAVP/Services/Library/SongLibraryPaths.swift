import Foundation

enum SongLibraryPathsError: Error {
    case documentsUnavailable
}

struct SongLibraryPaths {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func rootDirectoryURL() throws -> URL {
        try documentsDirectoryURL().appendingPathComponent(SongLibraryLayout.rootDirectoryName, isDirectory: true)
    }

    func scoresDirectoryURL() throws -> URL {
        try rootDirectoryURL().appendingPathComponent(SongLibraryLayout.scoresDirectoryName, isDirectory: true)
    }

    func audioDirectoryURL() throws -> URL {
        try rootDirectoryURL().appendingPathComponent(SongLibraryLayout.audioDirectoryName, isDirectory: true)
    }

    func indexFileURL() throws -> URL {
        try rootDirectoryURL().appendingPathComponent(SongLibraryLayout.indexFileName)
    }

    func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: rootDirectoryURL(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: scoresDirectoryURL(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: audioDirectoryURL(), withIntermediateDirectories: true)
    }

    private func documentsDirectoryURL() throws -> URL {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw SongLibraryPathsError.documentsUnavailable
        }
        return documentsURL
    }
}
