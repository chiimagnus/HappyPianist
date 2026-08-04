import Foundation

public struct PracticeProgressPaths: Sendable {
    public static let rootDirectoryName = "PracticeProgress"
    public static let fileName = "progress-v1.json"
    public static let recoveryBackupPrefix = "progress-v1.corrupted-"

    public let rootDirectoryURL: URL

    public init(rootDirectoryURL: URL? = nil) {
        self.rootDirectoryURL = rootDirectoryURL
            ?? URL.documentsDirectory.appending(path: Self.rootDirectoryName, directoryHint: .isDirectory)
    }

    public var fileURL: URL {
        rootDirectoryURL.appending(path: Self.fileName)
    }

    public func recoveryStagingURL(id: UUID) -> URL {
        rootDirectoryURL.appending(path: ".progress-v1.recovery-\(id.uuidString).tmp")
    }

    public func recoveryBackupName(id: UUID) -> String {
        "\(Self.recoveryBackupPrefix)\(id.uuidString).json"
    }

    public func recoveryBackupURL(id: UUID) -> URL {
        rootDirectoryURL.appending(path: recoveryBackupName(id: id))
    }
}
