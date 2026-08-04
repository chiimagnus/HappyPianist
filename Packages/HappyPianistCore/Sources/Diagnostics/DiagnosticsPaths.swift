import Foundation

public enum DiagnosticsPathsError: Error, Sendable {
    case documentsUnavailable
}

public struct DiagnosticsPaths: Sendable {
    public static let directoryName = "Diagnostics"

    private let rootOverride: URL?

    public init(rootDirectoryURL: URL? = nil) {
        rootOverride = rootDirectoryURL
    }

    public func rootDirectoryURL(using fileManager: FileManager) throws -> URL {
        if let rootOverride { return rootOverride }
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw DiagnosticsPathsError.documentsUnavailable
        }
        return documentsURL.appending(path: Self.directoryName, directoryHint: .isDirectory)
    }
}
