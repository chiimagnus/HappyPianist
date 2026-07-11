import Foundation

struct PracticeProgressPaths: Sendable {
    static let rootDirectoryName = "PracticeProgress"
    static let fileName = "progress-v1.json"

    let rootDirectoryURL: URL

    init(rootDirectoryURL: URL? = nil) {
        self.rootDirectoryURL = rootDirectoryURL
            ?? URL.documentsDirectory.appending(path: Self.rootDirectoryName, directoryHint: .isDirectory)
    }

    var fileURL: URL {
        rootDirectoryURL.appending(path: Self.fileName)
    }
}
