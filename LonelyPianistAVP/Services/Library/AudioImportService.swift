import Foundation

protocol AudioImportServiceProtocol {
    func importAudio(from sourceURL: URL) throws -> String
}

struct AudioImportService: AudioImportServiceProtocol {
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

    func importAudio(from sourceURL: URL) throws -> String {
        let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try paths.ensureDirectoriesExist()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: now()).replacingOccurrences(of: ":", with: "-")

        let sourceFileName = URL(fileURLWithPath: sourceURL.lastPathComponent).lastPathComponent
        let targetFileName = "\(timestamp)-\(sourceFileName)"
        let destinationURL = try uniqueDestinationURL(fileName: targetFileName)

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL.lastPathComponent
    }

    private func uniqueDestinationURL(fileName: String) throws -> URL {
        let audioDirectoryURL = try paths.audioDirectoryURL()
        var destinationURL = audioDirectoryURL.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: destinationURL.path()) == false {
            return destinationURL
        }

        let ext = destinationURL.pathExtension
        let base = destinationURL.deletingPathExtension().lastPathComponent
        destinationURL = audioDirectoryURL.appendingPathComponent("\(base)-\(UUID().uuidString)")
        if ext.isEmpty == false {
            destinationURL.appendPathExtension(ext)
        }

        return destinationURL
    }
}
