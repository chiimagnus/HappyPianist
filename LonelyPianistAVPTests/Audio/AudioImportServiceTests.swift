import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func audioImportServiceCopiesFileIntoAudioDirectory() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "AudioImportServiceTests-docs")
    let externalURL = try makeTemporaryDirectory(prefix: "AudioImportServiceTests-external")
    defer {
        try? FileManager.default.removeItem(at: documentsURL)
        try? FileManager.default.removeItem(at: externalURL)
    }

    let sourceURL = externalURL.appendingPathComponent("sample.mp3")
    try Data("audio".utf8).write(to: sourceURL)

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = SongLibraryPaths(fileManager: fileManager)
    let service = AudioImportService(
        fileManager: fileManager,
        paths: paths,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let storedFileName = try service.importAudio(from: sourceURL)
    let storedURL = try paths.audioDirectoryURL().appendingPathComponent(storedFileName)

    #expect(storedFileName.contains("sample.mp3"))
    #expect(fileManager.fileExists(atPath: storedURL.path()))
}

private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
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
