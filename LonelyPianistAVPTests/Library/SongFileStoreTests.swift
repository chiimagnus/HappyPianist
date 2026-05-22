import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func songFileStoreImportsMusicXMLIntoScoresDirectory() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "SongFileStoreTests-docs")
    let externalURL = try makeTemporaryDirectory(prefix: "SongFileStoreTests-external")
    defer {
        try? FileManager.default.removeItem(at: documentsURL)
        try? FileManager.default.removeItem(at: externalURL)
    }

    let sourceURL = externalURL.appendingPathComponent("sample.musicxml")
    try Data("<score-partwise version=\"3.1\"></score-partwise>".utf8).write(to: sourceURL)

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = SongLibraryPaths(fileManager: fileManager)
    let fileStore = SongFileStore(
        fileManager: fileManager,
        paths: paths,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let imported = try fileStore.importMusicXML(from: sourceURL)

    #expect(imported.sourceFileName == "sample.musicxml")
    #expect(imported.storedFileName.contains("sample.musicxml"))
    #expect(fileManager.fileExists(atPath: imported.storedURL.path()))

    let scoresDirectory = try paths.scoresDirectoryURL().path()
    #expect(imported.storedURL.path().hasPrefix(scoresDirectory))
}

@Test
func songFileStoreDeleteRemovesScoreAndAudioFiles() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "SongFileStoreTests-delete")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = SongLibraryPaths(fileManager: fileManager)
    try paths.ensureDirectoriesExist()

    let scoreFileName = "to-delete.musicxml"
    let audioFileName = "to-delete.m4a"

    let scoreURL = try paths.scoresDirectoryURL().appendingPathComponent(scoreFileName)
    let audioURL = try paths.audioDirectoryURL().appendingPathComponent(audioFileName)

    try Data("score".utf8).write(to: scoreURL)
    try Data("audio".utf8).write(to: audioURL)

    let fileStore = SongFileStore(fileManager: fileManager, paths: paths)

    try fileStore.deleteScoreFile(named: scoreFileName)
    try fileStore.deleteAudioFile(named: audioFileName)

    #expect(fileManager.fileExists(atPath: scoreURL.path()) == false)
    #expect(fileManager.fileExists(atPath: audioURL.path()) == false)
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
