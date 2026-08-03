import Foundation
import Synchronization
@testable import Library
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

    let fileManager: FileManager = AudioImportTestDocumentsFileManager(documentsURL: documentsURL)
    let paths = SongLibraryPaths(fileManager: fileManager)
    let audioDirectoryURL = documentsURL
        .appending(path: SongLibraryLayout.rootDirectoryName, directoryHint: .isDirectory)
        .appending(path: SongLibraryLayout.audioDirectoryName, directoryHint: .isDirectory)
    let securityScope = AudioImportSecurityScopeSpy()
    let service = AudioImportService(
        fileManager: fileManager,
        paths: paths,
        now: { Date(timeIntervalSince1970: 1_700_000_000) },
        securityScopedResourceAccessor: securityScope
    )

    let storedFileName = try await service.importAudio(from: sourceURL)
    let storedURL = audioDirectoryURL.appending(path: storedFileName)

    #expect(storedFileName.contains("sample.mp3"))
    #expect(FileManager.default.fileExists(atPath: storedURL.path()))
    #expect(securityScope.accessedURLs == [sourceURL])
    #expect(securityScope.releasedURLs == [sourceURL])
}

@Test
func audioImportServiceRejectsUnsupportedFilesBeforeOpeningSecurityScope() async throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "AudioImportServiceTests-docs")
    let externalURL = try makeTemporaryDirectory(prefix: "AudioImportServiceTests-external")
    defer {
        try? FileManager.default.removeItem(at: documentsURL)
        try? FileManager.default.removeItem(at: externalURL)
    }

    let sourceURL = externalURL.appending(path: "sample.wav")
    try Data("audio".utf8).write(to: sourceURL)
    let securityScope = AudioImportSecurityScopeSpy()
    let fileManager = AudioImportTestDocumentsFileManager(documentsURL: documentsURL)
    let service = AudioImportService(
        fileManager: fileManager,
        paths: SongLibraryPaths(fileManager: fileManager),
        securityScopedResourceAccessor: securityScope
    )

    await #expect(throws: AudioImportServiceError.unsupportedFileType("wav")) {
        try await service.importAudio(from: sourceURL)
    }
    #expect(securityScope.accessedURLs.isEmpty)
    #expect(securityScope.releasedURLs.isEmpty)
    #expect(
        FileManager.default.fileExists(
            atPath: documentsURL.appending(path: SongLibraryLayout.rootDirectoryName).path()
        ) == false
    )
}

private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private final class AudioImportTestDocumentsFileManager: FileManager {
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

private final class AudioImportSecurityScopeSpy: SecurityScopedResourceAccessing {
    private let state = Mutex((accessedURLs: [URL](), releasedURLs: [URL]()))

    var accessedURLs: [URL] {
        state.withLock { $0.accessedURLs }
    }

    var releasedURLs: [URL] {
        state.withLock { $0.releasedURLs }
    }

    func startAccessing(_ url: URL) -> Bool {
        state.withLock { $0.accessedURLs.append(url) }
        return true
    }

    func stopAccessing(_ url: URL) {
        state.withLock { $0.releasedURLs.append(url) }
    }
}
