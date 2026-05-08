import Foundation

enum RecordingTakeLibraryPathsError: Error {
    case documentsUnavailable
}

enum RecordingTakeLibraryLayout {
    static let rootDirectoryName = "TakeLibrary"
    static let takesFileName = "takes.json"
}

struct RecordingTakeLibraryPaths {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func rootDirectoryURL() throws -> URL {
        try documentsDirectoryURL()
            .appendingPathComponent(RecordingTakeLibraryLayout.rootDirectoryName, isDirectory: true)
    }

    func takesFileURL() throws -> URL {
        try rootDirectoryURL()
            .appendingPathComponent(RecordingTakeLibraryLayout.takesFileName)
    }

    func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: rootDirectoryURL(), withIntermediateDirectories: true)
    }

    private func documentsDirectoryURL() throws -> URL {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw RecordingTakeLibraryPathsError.documentsUnavailable
        }
        return documentsURL
    }
}
