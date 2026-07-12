import Foundation

enum DiagnosticsPathsError: Error {
    case documentsUnavailable
}

struct DiagnosticsPaths: @unchecked Sendable {
    static let directoryName = "Diagnostics"

    private let fileManager: FileManager
    private let rootOverride: URL?

    init(fileManager: FileManager = .default, rootDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        rootOverride = rootDirectoryURL
    }

    func rootDirectoryURL() throws -> URL {
        if let rootOverride {
            return rootOverride
        }
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw DiagnosticsPathsError.documentsUnavailable
        }
        return documentsURL.appending(path: Self.directoryName, directoryHint: .isDirectory)
    }

    func ensureDirectoryExists() throws {
        try fileManager.createDirectory(at: rootDirectoryURL(), withIntermediateDirectories: true)
    }
}
