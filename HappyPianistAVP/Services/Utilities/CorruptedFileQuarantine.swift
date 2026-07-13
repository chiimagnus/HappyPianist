import Foundation

enum CorruptedFileQuarantine {
    @discardableResult
    static func move(
        _ fileURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let fileExtension = fileURL.pathExtension
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let suffix = UUID().uuidString.lowercased()
        let backupName = fileExtension.isEmpty
            ? "\(stem).corrupt-\(suffix)"
            : "\(stem).corrupt-\(suffix).\(fileExtension)"
        let backupURL = fileURL.deletingLastPathComponent().appending(path: backupName)
        try fileManager.moveItem(at: fileURL, to: backupURL)
        return backupURL
    }
}
