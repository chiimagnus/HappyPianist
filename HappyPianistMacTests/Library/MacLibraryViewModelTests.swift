import Diagnostics
import Foundation
import HappyPianistTestFixtures
import Library
import Practice
import Synchronization
@testable import HappyPianistMac
import Testing

@MainActor
struct MacLibraryViewModelTests {
    @Test func importsOnlyALocalCopyAndReleasesTheSecurityScope() async throws {
        let fixture = try MacLibraryFixture()
        defer { fixture.remove() }
        let sourceURL = try fixture.copyFixture(named: "PracticeLearningLoopEightMeasures.musicxml")

        let stageResult = await fixture.service.stageImports(from: [sourceURL])
        let stagedImport = try #require(stageResult.items.first?.stagedImport)
        let journalData = try Data(contentsOf: fixture.paths.transactionJournalFileURL(operationID: stagedImport.id))
        #expect(fixture.containsExternalReference(journalData) == false)

        let processResult = await fixture.service.process(operationID: stagedImport.id)
        guard case let .committed(_, entry) = processResult else {
            Issue.record("Expected a committed import")
            return
        }

        let indexData = try Data(contentsOf: fixture.paths.indexFileURL())
        let copiedScoreData = try Data(contentsOf: fixture.paths.scoreFileURL(safeFileName: entry.musicXMLFileName))
        let sourceData = try Data(contentsOf: sourceURL)
        #expect(fixture.containsExternalReference(indexData) == false)
        #expect(copiedScoreData == sourceData)
        #expect(FileManager.default.fileExists(atPath: fixture.progressPaths.fileURL.path(percentEncoded: false)) == false)
        #expect(fixture.scope.accessedURLs == [sourceURL])
        #expect(fixture.scope.releasedURLs == [sourceURL])
    }

    @Test func recoversBeforeLoadingThenImportsAndPersistsTheSelectedEntry() async throws {
        let fixture = try MacLibraryFixture()
        defer { fixture.remove() }
        await fixture.viewModel.loadLibrary()
        #expect(fixture.viewModel.loadState == .ready)
        #expect(fixture.viewModel.entries.isEmpty)

        await fixture.viewModel.importMusicXML(from: [
            try fixture.copyFixture(named: "PracticeLearningLoopEightMeasures.musicxml"),
        ])

        #expect(fixture.viewModel.importState == .idle)
        let selectedEntryID = try #require(fixture.viewModel.selectedEntryID)
        #expect(fixture.viewModel.entries.map(\.id) == [selectedEntryID])
        #expect(try await fixture.indexStore.load().lastSelectedEntryID == selectedEntryID)
    }

    @Test func preservesABlockedRecoveryAsAUserAction() async throws {
        let fixture = try MacLibraryFixture(importTransactionService: BlockedImportTransactionService())
        defer { fixture.remove() }

        await fixture.viewModel.loadLibrary()

        #expect(fixture.viewModel.loadState == .recoveryBlocked("恢复事务尚未收敛。"))
    }
}

private struct MacLibraryFixture {
    let rootURL: URL
    let documentsURL: URL
    let externalURL: URL
    let paths: SongLibraryPaths
    let progressPaths: PracticeProgressPaths
    let indexStore: SongLibraryIndexStore
    let service: SongLibraryImportTransactionService
    let viewModel: MacLibraryViewModel
    let scope: MacSecurityScopeSpy

    @MainActor
    init(importTransactionService: (any SongLibraryImportTransactionServicing)? = nil) throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "HappyPianistMacLibraryTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        documentsURL = rootURL.appending(path: "Documents", directoryHint: .isDirectory)
        externalURL = rootURL.appending(path: "External", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalURL, withIntermediateDirectories: true)

        paths = SongLibraryPaths(
            fileManager: MacLibraryDocumentsFileManager(documentsURL: documentsURL)
        )
        progressPaths = PracticeProgressPaths(
            rootDirectoryURL: rootURL.appending(path: "PracticeProgress", directoryHint: .isDirectory)
        )
        indexStore = SongLibraryIndexStore(
            fileManager: MacLibraryDocumentsFileManager(documentsURL: documentsURL),
            paths: SongLibraryPaths(
                fileManager: MacLibraryDocumentsFileManager(documentsURL: documentsURL)
            )
        )
        scope = MacSecurityScopeSpy()
        service = SongLibraryImportTransactionService(
            indexStore: indexStore,
            paths: SongLibraryPaths(
                fileManager: MacLibraryDocumentsFileManager(documentsURL: documentsURL)
            ),
            fileManager: MacLibraryDocumentsFileManager(documentsURL: documentsURL),
            diagnostics: MacLibraryDiagnosticsReporter(),
            securityScopedResourceAccessor: scope
        )
        viewModel = MacLibraryViewModel(
            indexStore: indexStore,
            importTransactionService: importTransactionService ?? service,
            bundledProvider: EmptyMacLibraryProvider()
        )
    }

    func copyFixture(named name: String) throws -> URL {
        let destination = externalURL.appending(path: name)
        try FileManager.default.copyItem(at: HappyPianistTestFixtures.url(named: name), to: destination)
        return destination
    }

    func containsExternalReference(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8)?.contains(externalURL.path(percentEncoded: false)) == true
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private final class MacLibraryDocumentsFileManager: FileManager {
    private let documentsURL: URL

    init(documentsURL: URL) {
        self.documentsURL = documentsURL
        super.init()
    }

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        directory == .documentDirectory ? [documentsURL] : super.urls(for: directory, in: domainMask)
    }
}

private final class MacSecurityScopeSpy: SecurityScopedResourceAccessing {
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

private struct EmptyMacLibraryProvider: BundledSongLibraryProviderProtocol {
    func bundledEntries() -> [SongLibraryEntry] { [] }
    func musicXMLURL(fileName _: String) -> URL? { nil }
    func audioURL(fileName _: String) -> URL? { nil }
}

private actor MacLibraryDiagnosticsReporter: DiagnosticsReporting {
    func record(_: DiagnosticEvent) -> DiagnosticRecordResult {
        DiagnosticRecordResult(persistedForExport: false)
    }
}

private actor BlockedImportTransactionService: SongLibraryImportTransactionServicing {
    func recoverPendingTransactions() -> SongLibraryTransactionRecoveryResult {
        .blocked(SongLibraryBlockedImport(operationID: nil, message: "恢复事务尚未收敛。"))
    }

    func stageImports(from _: [URL]) -> SongLibraryImportBatchStageResult {
        SongLibraryImportBatchStageResult(items: [], blocked: nil)
    }

    func process(operationID _: UUID) -> SongLibraryImportProcessResult {
        .blocked(SongLibraryBlockedImport(operationID: nil, message: "恢复事务尚未收敛。"))
    }

    func confirm(operationID _: UUID) -> SongLibraryImportProcessResult {
        .blocked(SongLibraryBlockedImport(operationID: nil, message: "恢复事务尚未收敛。"))
    }

    func cancel(operationID _: UUID) -> Bool { false }
}

private extension SongLibraryImportBatchItem {
    var stagedImport: SongLibraryStagedImport? {
        guard case let .staged(stagedImport) = self else { return nil }
        return stagedImport
    }
}
