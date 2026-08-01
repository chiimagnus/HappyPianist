import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func audioImportServiceCopiesFileIntoAudioDirectory() async throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "AudioImportServiceTests-docs")
    let externalURL = try makeTemporaryDirectory(prefix: "AudioImportServiceTests-external")
    defer {
        try? FileManager.default.removeItem(at: documentsURL)
        try? FileManager.default.removeItem(at: externalURL)
    }

    let sourceURL = externalURL.appending(path: "sample.mp3")
    try Data("audio".utf8).write(to: sourceURL)

    let fileManager: FileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = SongLibraryPaths(fileManager: fileManager)
    let audioDirectoryURL = documentsURL
        .appending(path: SongLibraryLayout.rootDirectoryName, directoryHint: .isDirectory)
        .appending(path: SongLibraryLayout.audioDirectoryName, directoryHint: .isDirectory)
    let service = AudioImportService(
        fileManager: fileManager,
        paths: paths,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let storedFileName = try await service.importAudio(from: sourceURL)
    let storedURL = audioDirectoryURL.appending(path: storedFileName)

    #expect(storedFileName.contains("sample.mp3"))
    #expect(FileManager.default.fileExists(atPath: storedURL.path()))
}

private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private final class TestDocumentsFileManager: FileManager {
    private let documentsURL: URL

    init(documentsURL: URL) {
        self.documentsURL = documentsURL
        super.init()
    }

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        if directory == .documentDirectory {
            return [documentsURL]
        }
        return super.urls(for: directory, in: domainMask)
    }
}
