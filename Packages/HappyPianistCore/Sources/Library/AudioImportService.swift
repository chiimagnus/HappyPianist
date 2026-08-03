import Foundation

public protocol AudioImportServiceProtocol: Actor {
    func importAudio(from sourceURL: URL) async throws -> String
}

public enum AudioImportServiceError: LocalizedError, Equatable {
    case unsupportedFileType(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            "仅支持导入 mp3 或 m4a 音频文件。"
        }
    }
}

public actor AudioImportService: AudioImportServiceProtocol {
    public static let supportedFileExtensions = ["mp3", "m4a"]

    private let fileManager: FileManager
    private let paths: SongLibraryPaths
    private let now: @Sendable () -> Date
    private let securityScopedResourceAccessor: any SecurityScopedResourceAccessing

    public init(
        fileManager: FileManager = .default,
        paths: SongLibraryPaths? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        securityScopedResourceAccessor: any SecurityScopedResourceAccessing = LiveSecurityScopedResourceAccessor()
    ) {
        self.fileManager = fileManager
        self.paths = paths ?? SongLibraryPaths(fileManager: fileManager)
        self.now = now
        self.securityScopedResourceAccessor = securityScopedResourceAccessor
    }

    public static func isSupported(_ sourceURL: URL) -> Bool {
        supportedFileExtensions.contains(sourceURL.pathExtension.lowercased())
    }

    public func importAudio(from sourceURL: URL) async throws -> String {
        let sourceFileName = sourceURL.lastPathComponent
        guard sourceFileName.isEmpty == false,
              sourceFileName != ".",
              sourceFileName != "..",
              URL(fileURLWithPath: sourceFileName).lastPathComponent == sourceFileName
        else { throw SongFileStoreError.invalidFileName(sourceFileName) }
        guard Self.isSupported(sourceURL) else {
            throw AudioImportServiceError.unsupportedFileType(sourceURL.pathExtension)
        }

        let hasScopedAccess = securityScopedResourceAccessor.startAccessing(sourceURL)
        defer {
            if hasScopedAccess { securityScopedResourceAccessor.stopAccessing(sourceURL) }
        }
        try paths.ensureDirectoriesExist()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: now()).replacing(":", with: "-")
        let destinationURL = try uniqueDestinationURL(fileName: "\(timestamp)-\(sourceFileName)")
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL.lastPathComponent
    }

    private func uniqueDestinationURL(fileName: String) throws -> URL {
        let audioDirectoryURL = try paths.audioDirectoryURL()
        var destinationURL = audioDirectoryURL.appending(path: fileName)
        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) == false { return destinationURL }
        let ext = destinationURL.pathExtension
        let base = destinationURL.deletingPathExtension().lastPathComponent
        destinationURL = audioDirectoryURL.appending(path: "\(base)-\(UUID().uuidString)")
        if ext.isEmpty == false { destinationURL.appendPathExtension(ext) }
        return destinationURL
    }
}
