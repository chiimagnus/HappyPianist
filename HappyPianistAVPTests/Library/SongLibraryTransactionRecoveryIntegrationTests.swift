import CryptoKit
import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func recoveryProcessesOwnedOperationsInOrderThenBlocksTamperedFactsIdempotently() async throws {
    let fixture = try ImportTransactionFixture()
    defer { fixture.remove() }
    try fixture.paths.ensureDirectoriesExist()
    let ownedID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let tamperedID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let ownedData = Data("owned-stage".utf8)
    try fixture.writeFile(
        ownedData,
        to: fixture.paths.transactionStageFileURL(
            operationID: ownedID,
            safeFileName: "owned.musicxml"
        )
    )
    try fixture.writeJournal(
        SongLibraryImportJournal(
            operationID: ownedID,
            kind: .unclassified,
            phase: .staged,
            safeFileName: "owned.musicxml",
            stagedFingerprint: transactionFingerprint(ownedData)
        )
    )

    let expected = Data("expected-target".utf8)
    let external = Data("external-target".utf8)
    let target = try fixture.paths.scoreFileURL(safeFileName: "tampered.musicxml")
    try external.write(to: target)
    try fixture.writeJournal(
        SongLibraryImportJournal(
            operationID: tamperedID,
            kind: .newImport,
            phase: .targetInstalled,
            safeFileName: "tampered.musicxml",
            stagedFingerprint: transactionFingerprint(expected),
            newEntry: SongLibraryNewEntryPayload(
                songID: UUID(),
                displayName: "tampered",
                musicXMLFileName: "tampered.musicxml",
                importedAt: Date(timeIntervalSince1970: 1_700_000_500),
                scoreFileVersionID: UUID()
            )
        )
    )

    guard case .blocked = await fixture.service.recoverPendingTransactions() else {
        Issue.record("Expected tampered operation to block recovery")
        return
    }
    #expect(
        FileManager.default.fileExists(
            atPath: try fixture.paths.transactionOperationDirectoryURL(operationID: ownedID)
                .path(percentEncoded: false)
        ) == false
    )
    #expect(try Data(contentsOf: target) == external)

    guard case .blocked = await fixture.service.recoverPendingTransactions() else {
        Issue.record("Expected repeated recovery to remain blocked")
        return
    }
    #expect(try Data(contentsOf: target) == external)
}

@Test
func transactionJournalAndDiagnosticsArchiveExcludeSourcePathsAndScoreContent() async throws {
    let exportRoot = FileManager.default.temporaryDirectory.appending(
        path: "SongLibraryTransactionPrivacy-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: exportRoot) }
    let exportStore = FileDiagnosticsStore(
        paths: DiagnosticsPaths(rootDirectoryURL: exportRoot)
    )
    let reporter = AppDiagnosticsReporter(
        systemSink: SilentDiagnosticsSink(),
        exportStore: exportStore
    )
    let fixture = try ImportTransactionFixture(diagnostics: reporter)
    defer { fixture.remove() }
    try fixture.paths.ensureDirectoriesExist()
    let first = transactionEntry(name: "private.musicxml")
    var second = transactionEntry(name: "other.musicxml")
    second.musicXMLFileName = "private.musicxml"
    _ = try await fixture.indexStore.appendUserEntry(first)
    _ = try await fixture.indexStore.appendUserEntry(second)
    try Data("old".utf8).write(
        to: fixture.paths.scoreFileURL(safeFileName: "private.musicxml")
    )
    let xml = "<score-partwise>SECRET-NOTES</score-partwise>"
    let source = try fixture.makeSource(name: "private.musicxml", contents: xml)
    let staged = await fixture.service.stageImports(from: [source])
    guard case let .staged(descriptor)? = staged.items.first else {
        Issue.record("Expected staged private score")
        return
    }
    let journalData = try Data(
        contentsOf: fixture.paths.transactionJournalFileURL(operationID: descriptor.id)
    )
    let journalText = try #require(String(data: journalData, encoding: .utf8))
    #expect(journalText.contains("file://") == false)
    #expect(journalText.contains(fixture.documentsURL.path(percentEncoded: false)) == false)
    #expect(journalText.contains(fixture.externalURL.path(percentEncoded: false)) == false)
    #expect(journalText.contains("SECRET-NOTES") == false)

    guard case .blocked = await fixture.service.process(operationID: descriptor.id) else {
        Issue.record("Expected ambiguous import to block")
        return
    }
    let exported = try await exportStore.loadEventsForExport(referenceDate: .now)
    #expect(exported.isEmpty)
}

private struct SilentDiagnosticsSink: SystemDiagnosticsSinkProtocol {
    func record(_: DiagnosticEvent) {}
}

private func transactionEntry(name: String) -> SongLibraryEntry {
    SongLibraryEntry(
        id: UUID(),
        displayName: name,
        musicXMLFileName: name,
        scoreFileVersionID: UUID(),
        importedAt: .distantPast,
        audioFileName: nil
    )
}

private func transactionFingerprint(_ data: Data) throws -> TransactionFileFingerprint {
    let digest = SHA256.hash(data: data).map { byte in
        let digits = Array("0123456789abcdef")
        return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0f)]])
    }.joined()
    return try TransactionFileFingerprint(byteCount: Int64(data.count), sha256: digest)
}
