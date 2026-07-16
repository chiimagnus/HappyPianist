import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func transactionRecoveryHasEmptyDirectoryFastPath() async throws {
    let fixture = try TransactionRecoveryFixture()
    defer { fixture.remove() }

    #expect(await fixture.service.recoverPendingTransactions() == .recovered)
    #expect(
        try FileManager.default.contentsOfDirectory(
            at: fixture.paths.transactionsDirectoryURL(),
            includingPropertiesForKeys: nil
        ).isEmpty
    )
}

@Test
func transactionRecoveryCleansJournalLessOwnedStageScratch() async throws {
    let fixture = try TransactionRecoveryFixture()
    defer { fixture.remove() }
    let operationID = UUID()
    let stageURL = try fixture.paths.transactionStageFileURL(
        operationID: operationID,
        safeFileName: "score.musicxml"
    )
    try FileManager.default.createDirectory(
        at: stageURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("partial".utf8).write(to: stageURL)

    #expect(await fixture.service.recoverPendingTransactions() == .recovered)
    #expect(
        try FileManager.default.fileExists(
            atPath: fixture.paths.transactionOperationDirectoryURL(operationID: operationID).path(percentEncoded: false)
        ) == false
    )
}

@Test
func transactionRecoveryBlocksUnknownOrSymlinkedScratch() async throws {
    let fixture = try TransactionRecoveryFixture()
    defer { fixture.remove() }
    let operationID = UUID()
    let operationURL = try fixture.paths.transactionOperationDirectoryURL(operationID: operationID)
    try FileManager.default.createDirectory(at: operationURL, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        at: operationURL.appending(path: "stage"),
        withDestinationURL: fixture.documentsURL
    )

    let result = await fixture.service.recoverPendingTransactions()

    guard case let .blocked(blocked) = result else {
        Issue.record("Expected blocking recovery")
        return
    }
    #expect(blocked.operationID == operationID)
    #expect(FileManager.default.fileExists(atPath: operationURL.path(percentEncoded: false)))
}

private struct TransactionRecoveryFixture {
    let documentsURL: URL
    let paths: SongLibraryPaths
    let service: SongLibraryImportTransactionService

    init() throws {
        documentsURL = FileManager.default.temporaryDirectory.appending(
            path: "SongLibraryTransactionRecoveryTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        paths = SongLibraryPaths(
            fileManager: TransactionRecoveryDocumentsFileManager(documentsURL: documentsURL)
        )
        let indexStore = SongLibraryIndexStore(
            fileManager: TransactionRecoveryDocumentsFileManager(documentsURL: documentsURL),
            paths: SongLibraryPaths(
                fileManager: TransactionRecoveryDocumentsFileManager(documentsURL: documentsURL)
            )
        )
        service = SongLibraryImportTransactionService(
            indexStore: indexStore,
            paths: SongLibraryPaths(
                fileManager: TransactionRecoveryDocumentsFileManager(documentsURL: documentsURL)
            ),
            fileManager: TransactionRecoveryDocumentsFileManager(documentsURL: documentsURL),
            diagnostics: TransactionRecoveryDiagnosticsReporter()
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: documentsURL)
    }
}

private final class TransactionRecoveryDocumentsFileManager: FileManager {
    private let documentsURL: URL

    init(documentsURL: URL) {
        self.documentsURL = documentsURL
        super.init()
    }

    override func urls(
        for directory: SearchPathDirectory,
        in domainMask: SearchPathDomainMask
    ) -> [URL] {
        directory == .documentDirectory
            ? [documentsURL]
            : super.urls(for: directory, in: domainMask)
    }
}

private actor TransactionRecoveryDiagnosticsReporter: DiagnosticsReporting {
    func record(_: DiagnosticEvent) -> DiagnosticRecordResult {
        DiagnosticRecordResult(persistedForExport: false)
    }
}
