import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func entryResolverResolvesBundledEntryByIDWithSafeReference() async throws {
    let scoreURL = FileManager.default.temporaryDirectory.appending(
        path: "resolver-bundled-\(UUID().uuidString).musicxml"
    )
    try Data("score".utf8).write(to: scoreURL)
    defer { try? FileManager.default.removeItem(at: scoreURL) }
    let bundled = resolverEntry(name: "Shared", fileName: scoreURL.lastPathComponent, isBundled: true)
    let user = resolverEntry(name: "Shared", fileName: "user.musicxml")
    let indexStore = ResolverIndexStore(index: SongLibraryIndex(entries: [user]))
    let resolver = SongLibraryEntryResolver(
        indexStore: indexStore,
        bundledProvider: ResolverBundledProvider(entries: [bundled], scoreURL: scoreURL),
        fileStore: ResolverFileStore(result: .url(URL(fileURLWithPath: "/tmp/user.musicxml")))
    )

    let resolved = try await resolver.resolve(songID: bundled.id)

    #expect(resolved.entry == bundled)
    #expect(resolved.scoreURL == scoreURL)
    #expect(resolved.diagnosticFileReference?.relativePath == "Bundle/\(scoreURL.lastPathComponent)")

    let resolvedUser = try await resolver.resolve(songID: user.id)
    #expect(resolvedUser.entry == user)
    #expect(resolvedUser.diagnosticFileReference?.relativePath == "SongLibrary/scores/user.musicxml")
}

@Test
func entryResolverReadsLatestUserEntryWithoutCaching() async throws {
    let documentsURL = try resolverTemporaryDirectory(prefix: "resolver-latest")
    defer { try? FileManager.default.removeItem(at: documentsURL) }
    let fileManager: FileManager = ResolverDocumentsFileManager(documentsURL: documentsURL)
    let paths = SongLibraryPaths(fileManager: fileManager)
    try paths.ensureDirectoriesExist()
    let firstFileName = "first.musicxml"
    let secondFileName = "second.musicxml"
    try Data("first".utf8).write(to: try paths.scoresDirectoryURL().appending(path: firstFileName))
    try Data("second".utf8).write(to: try paths.scoresDirectoryURL().appending(path: secondFileName))
    let songID = UUID()
    let firstEntry = SongLibraryEntry(
        id: songID,
        displayName: "Same Song",
        musicXMLFileName: firstFileName,
        importedAt: .now,
        audioFileName: nil
    )
    let secondEntry = SongLibraryEntry(
        id: songID,
        displayName: "Same Song Replaced",
        musicXMLFileName: secondFileName,
        importedAt: .now,
        audioFileName: nil
    )
    let indexStore = ResolverIndexStore(index: SongLibraryIndex(entries: [firstEntry]))
    let resolver = SongLibraryEntryResolver(
        indexStore: indexStore,
        bundledProvider: ResolverBundledProvider(entries: [], scoreURL: nil),
        fileStore: SongFileStore(fileManager: fileManager, paths: paths)
    )

    let first = try await resolver.resolve(songID: songID)
    await indexStore.replace(entries: [secondEntry])
    let second = try await resolver.resolve(songID: songID)

    #expect(first.entry == firstEntry)
    #expect(second.entry == secondEntry)
    #expect(second.scoreURL.lastPathComponent == secondFileName)
    #expect(second.diagnosticFileReference?.relativePath == "SongLibrary/scores/second.musicxml")
}

@Test
func entryResolverMapsMissingEntryAndBundledResource() async throws {
    let missingID = UUID()
    let indexStore = ResolverIndexStore(index: .empty)
    let emptyResolver = SongLibraryEntryResolver(
        indexStore: indexStore,
        bundledProvider: ResolverBundledProvider(entries: [], scoreURL: nil),
        fileStore: ResolverFileStore(result: .missing)
    )
    let missingEntryError = await resolutionError {
        try await emptyResolver.resolve(songID: missingID)
    }
    #expect(missingEntryError?.preparationError == .scoreFileNotFound)
    #expect(missingEntryError?.diagnosticFileReference == nil)

    let bundled = resolverEntry(name: "Missing", fileName: "missing.musicxml", isBundled: true)
    let bundledResolver = SongLibraryEntryResolver(
        indexStore: indexStore,
        bundledProvider: ResolverBundledProvider(entries: [bundled], scoreURL: nil),
        fileStore: ResolverFileStore(result: .missing)
    )
    let missingFileError = await resolutionError {
        try await bundledResolver.resolve(songID: bundled.id)
    }
    #expect(missingFileError?.preparationError == .scoreFileNotFound)
    #expect(missingFileError?.diagnosticFileReference?.relativePath == "Bundle/missing.musicxml")

    let user = resolverEntry(name: "Missing User", fileName: "missing-user.musicxml")
    await indexStore.replace(entries: [user])
    let userResolver = SongLibraryEntryResolver(
        indexStore: indexStore,
        bundledProvider: ResolverBundledProvider(entries: [], scoreURL: nil),
        fileStore: ResolverFileStore(result: .missing)
    )
    let missingUserFileError = await resolutionError {
        try await userResolver.resolve(songID: user.id)
    }
    #expect(missingUserFileError?.preparationError == .scoreFileNotFound)
    #expect(
        missingUserFileError?.diagnosticFileReference?.relativePath ==
            "SongLibrary/scores/missing-user.musicxml"
    )
}

@Test
func entryResolverRejectsBundledNonRegularResource() async throws {
    let directoryURL = try resolverTemporaryDirectory(prefix: "resolver-bundled-directory")
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let bundled = resolverEntry(name: "Directory", fileName: "directory.musicxml", isBundled: true)
    let resolver = SongLibraryEntryResolver(
        indexStore: ResolverIndexStore(index: .empty),
        bundledProvider: ResolverBundledProvider(entries: [bundled], scoreURL: directoryURL),
        fileStore: ResolverFileStore(result: .missing)
    )

    let error = await resolutionError {
        try await resolver.resolve(songID: bundled.id)
    }

    guard case .scoreFileUnreadable = error?.preparationError else {
        Issue.record("Expected a non-regular bundled resource to be rejected")
        return
    }
    #expect(error?.diagnosticFileReference?.relativePath == "Bundle/directory.musicxml")
}

@Test
func entryResolverRejectsUnsafeUserFileNameWithoutLeakingPath() async throws {
    let entry = resolverEntry(name: "Unsafe", fileName: "../private.musicxml")
    let resolver = SongLibraryEntryResolver(
        indexStore: ResolverIndexStore(index: SongLibraryIndex(entries: [entry])),
        bundledProvider: ResolverBundledProvider(entries: [], scoreURL: nil),
        fileStore: ResolverFileStore(result: .error(.invalidFileName("../private.musicxml")))
    )

    let error = await resolutionError {
        try await resolver.resolve(songID: entry.id)
    }

    guard case .scoreFileUnreadable = error?.preparationError else {
        Issue.record("Expected unreadable score error")
        return
    }
    #expect(error?.diagnosticFileReference?.relativePath == "SongLibrary/scores/private.musicxml")
    #expect(String(describing: error?.preparationError).contains("../private.musicxml") == false)
}

@Test
func songFileStoreRejectsSymbolicLinkScore() async throws {
    let documentsURL = try resolverTemporaryDirectory(prefix: "resolver-symlink-docs")
    let outsideURL = try resolverTemporaryDirectory(prefix: "resolver-symlink-outside")
    defer {
        try? FileManager.default.removeItem(at: documentsURL)
        try? FileManager.default.removeItem(at: outsideURL)
    }
    let fileManager: FileManager = ResolverDocumentsFileManager(documentsURL: documentsURL)
    let paths = SongLibraryPaths(fileManager: fileManager)
    try paths.ensureDirectoriesExist()
    let targetURL = outsideURL.appending(path: "target.musicxml")
    try Data("score".utf8).write(to: targetURL)
    let linkURL = try paths.scoresDirectoryURL().appending(path: "link.musicxml")
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
    let entry = resolverEntry(name: "Link", fileName: linkURL.lastPathComponent)
    let resolver = SongLibraryEntryResolver(
        indexStore: ResolverIndexStore(index: SongLibraryIndex(entries: [entry])),
        bundledProvider: ResolverBundledProvider(entries: [], scoreURL: nil),
        fileStore: SongFileStore(fileManager: fileManager, paths: paths)
    )

    let error = await resolutionError {
        try await resolver.resolve(songID: entry.id)
    }

    guard case .scoreFileUnreadable = error?.preparationError else {
        Issue.record("Expected symbolic link to be rejected")
        return
    }
}

private func resolutionError(
    operation: () async throws -> ResolvedSongLibraryEntry
) async -> SongLibraryEntryResolutionError? {
    do {
        _ = try await operation()
        Issue.record("Expected entry resolution to fail")
        return nil
    } catch let error as SongLibraryEntryResolutionError {
        return error
    } catch {
        Issue.record("Unexpected error: \(error)")
        return nil
    }
}

private func resolverEntry(
    name: String,
    fileName: String,
    isBundled: Bool = false
) -> SongLibraryEntry {
    SongLibraryEntry(
        id: UUID(),
        displayName: name,
        musicXMLFileName: fileName,
        importedAt: .now,
        audioFileName: nil,
        isBundled: isBundled
    )
}

private actor ResolverIndexStore: SongLibraryIndexStoreProtocol {
    private var index: SongLibraryIndex

    init(index: SongLibraryIndex) {
        self.index = index
    }

    func replace(entries: [SongLibraryEntry]) {
        index.entries = entries
    }

    func load() throws -> SongLibraryIndex { index }
    func setLastSelectedEntryID(_ entryID: UUID?) throws -> SongLibraryIndex {
        index.lastSelectedEntryID = entryID
        return index
    }
    func appendUserEntry(_ entry: SongLibraryEntry) throws -> SongLibraryIndex {
        index.entries.append(entry)
        return index
    }
    func removeUserEntry(
        id: UUID,
        fallbackLastSelectedEntryID _: UUID?
    ) throws -> SongLibraryEntryMutationResult {
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == id }) else {
            return .notFound(index: index)
        }
        return .applied(index: index, entry: index.entries.remove(at: entryIndex))
    }
    func updateAudioFileName(
        entryID: UUID,
        expectedCurrentFileName _: String?,
        newFileName _: String?
    ) throws -> SongLibraryEntryMutationResult {
        guard let entry = index.entries.first(where: { $0.id == entryID }) else {
            return .notFound(index: index)
        }
        return .applied(index: index, entry: entry)
    }
}

private actor ResolverFileStore: SongFileStoreProtocol {
    let result: ResolverFileStoreResult

    init(result: ResolverFileStoreResult) {
        self.result = result
    }

    func scoreFileURL(fileName _: String) async throws -> URL {
        switch result {
        case let .url(url): url
        case .missing: throw CocoaError(.fileNoSuchFile)
        case let .error(error): throw error
        }
    }
    func audioFileURL(fileName _: String) async throws -> URL { throw CocoaError(.fileNoSuchFile) }
    func deleteScoreFile(named _: String) async throws {}
    func deleteAudioFile(named _: String) async throws {}
}

private enum ResolverFileStoreResult: Sendable {
    case url(URL)
    case missing
    case error(SongFileStoreError)
}

private struct ResolverBundledProvider: BundledSongLibraryProviderProtocol {
    let entries: [SongLibraryEntry]
    let scoreURL: URL?

    func bundledEntries() -> [SongLibraryEntry] { entries }
    func musicXMLURL(fileName _: String) -> URL? { scoreURL }
    func audioURL(fileName _: String) -> URL? { nil }
}

private func resolverTemporaryDirectory(prefix: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory.appending(
        path: "\(prefix)-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private final class ResolverDocumentsFileManager: FileManager {
    private let documentsURL: URL

    init(documentsURL: URL) {
        self.documentsURL = documentsURL
        super.init()
    }

    override func urls(
        for directory: SearchPathDirectory,
        in domainMask: SearchPathDomainMask
    ) -> [URL] {
        directory == .documentDirectory ? [documentsURL] : super.urls(for: directory, in: domainMask)
    }
}
