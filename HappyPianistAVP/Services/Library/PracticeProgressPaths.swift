import Foundation

struct PracticeProgressPaths {
    static let rootDirectoryName = "PracticeProgress"
    static let fileName = "progress-v1.json"
    static let recoveryBackupPrefix = "progress-v1.corrupted-"

    let rootDirectoryURL: URL

    init(rootDirectoryURL: URL? = nil) {
        self.rootDirectoryURL = rootDirectoryURL
            ?? URL.documentsDirectory.appending(path: Self.rootDirectoryName, directoryHint: .isDirectory)
    }

    var fileURL: URL {
        rootDirectoryURL.appending(path: Self.fileName)
    }

    func recoveryStagingURL(id: UUID) -> URL {
        rootDirectoryURL.appending(path: ".progress-v1.recovery-\(id.uuidString).tmp")
    }

    func recoveryBackupName(id: UUID) -> String {
        "\(Self.recoveryBackupPrefix)\(id.uuidString).json"
    }

    func recoveryBackupURL(id: UUID) -> URL {
        rootDirectoryURL.appending(path: recoveryBackupName(id: id))
    }
}
