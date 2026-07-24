import Foundation

enum DiagnosticsPathsError: Error {
    case documentsUnavailable
}

struct DiagnosticsPaths {
    static let directoryName = "Diagnostics"

    private let rootOverride: URL?

    init(rootDirectoryURL: URL? = nil) {
        rootOverride = rootDirectoryURL
    }

    func rootDirectoryURL(using fileManager: FileManager) throws -> URL {
        if let rootOverride {
            return rootOverride
        }
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw DiagnosticsPathsError.documentsUnavailable
        }
        return documentsURL.appending(path: Self.directoryName, directoryHint: .isDirectory)
    }
}
