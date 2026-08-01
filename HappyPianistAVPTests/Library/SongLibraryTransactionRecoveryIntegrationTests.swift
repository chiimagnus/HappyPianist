import CryptoKit
import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func recoveryProcessesOwnedOperationsInOrderThenBlocksTamperedFactsIdempotently() async throws {
    let diagnostics = RecordingTransactionDiagnosticsReporter()
    let fixture = try ImportTransactionFixture(diagnostics: diagnostics)
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
        try FileManager.default.fileExists(
            atPath: fixture.paths.transactionOperationDirectoryURL(operationID: ownedID)
                .path(percentEncoded: false)
        ) == false
    )
    #expect(try Data(contentsOf: target) == external)

    guard case .blocked = await fixture.service.recoverPendingTransactions() else {
        Issue.record("Expected repeated recovery to remain blocked")
        return
    }
    #expect(try Data(contentsOf: target) == external)
    let recoveryEvent = await diagnostics.events.first {
        $0.code == .libraryImportRecoveryAction && $0.operationID == tamperedID
    }
    #expect(recoveryEvent?.operationID == tamperedID)
    #expect(recoveryEvent?.safeFileName == "tampered.musicxml")
    #expect(recoveryEvent?.transactionKind == SongLibraryImportOperationKind.newImport.rawValue)
    #expect(recoveryEvent?.transactionPhase == SongLibraryImportJournalPhase.targetInstalled.rawValue)
    #expect(recoveryEvent?.reason.contains("action=block") == true)
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
    let systemSink = RecordingDiagnosticsSink()
    let reporter = AppDiagnosticsReporter(
        systemSink: systemSink,
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
    let stageEvents = systemSink.events.filter { $0.code == .libraryImportStage }
    #expect(stageEvents.contains { $0.stage == "stageImport.access" && $0.reason == "accessAcquired=false" })
    #expect(stageEvents.contains { $0.stage == "stageImport.result" && $0.reason == "staged" })
    #expect(stageEvents.allSatisfy { $0.operationID == descriptor.id })
    #expect(stageEvents.allSatisfy { $0.safeFileName == "private.musicxml" })
    #expect(stageEvents.allSatisfy { event in
        let text = event.textRepresentation
        return text.contains("SECRET-NOTES") == false
            && text.contains(fixture.documentsURL.path(percentEncoded: false)) == false
            && text.contains(fixture.externalURL.path(percentEncoded: false)) == false
            && text.contains("sha256") == false
    })

    guard case .blocked = await fixture.service.process(operationID: descriptor.id) else {
        Issue.record("Expected ambiguous import to block")
        return
    }
    let exported = try await exportStore.loadEventsForExport(referenceDate: .now)
    #expect(exported.isEmpty)
}

@Test
func recoveryBlocksJournalWhoseIndexedPayloadNamesAnotherFile() async throws {
    let fixture = try ImportTransactionFixture()
    defer { fixture.remove() }
    try fixture.paths.ensureDirectoriesExist()
    let operationID = UUID()
    let targetData = Data("verified-target".utf8)
    let safeFileName = "verified.musicxml"
    try targetData.write(to: fixture.paths.scoreFileURL(safeFileName: safeFileName))
    let valid = try SongLibraryImportJournal(
        operationID: operationID,
        kind: .newImport,
        phase: .targetInstalled,
        safeFileName: safeFileName,
        stagedFingerprint: transactionFingerprint(targetData),
        newEntry: SongLibraryNewEntryPayload(
            songID: UUID(),
            displayName: "verified",
            musicXMLFileName: safeFileName,
            importedAt: Date(timeIntervalSince1970: 1_700_000_500),
            scoreFileVersionID: UUID()
        )
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .deferredToDate
    var object = try #require(
        JSONSerialization.jsonObject(with: encoder.encode(valid)) as? [String: Any]
    )
    var payload = try #require(object["newEntry"] as? [String: Any])
    payload["musicXMLFileName"] = "different.musicxml"
    object["newEntry"] = payload
    let journalURL = try fixture.paths.transactionJournalFileURL(operationID: operationID)
    try FileManager.default.createDirectory(
        at: journalURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try JSONSerialization.data(withJSONObject: object).write(to: journalURL)

    guard case .blocked = await fixture.service.recoverPendingTransactions() else {
        Issue.record("Expected mismatched payload identity to block recovery")
        return
    }
    #expect(try await fixture.indexStore.load().entries.isEmpty)
    #expect(try Data(contentsOf: fixture.paths.scoreFileURL(safeFileName: safeFileName)) == targetData)
}

@Test
func replacementJournalRejectsPayloadForAnotherSongIdentity() throws {
    let fingerprint = try transactionFingerprint(Data("score".utf8))
    let expectedSongID = UUID()

    #expect(throws: SongLibraryImportTransactionModelError.inconsistentResolvedIdentity) {
        try SongLibraryImportJournal(
            operationID: UUID(),
            kind: .indexedReplace,
            phase: .targetInstalled,
            safeFileName: "score.musicxml",
            stagedFingerprint: fingerprint,
            backupFingerprint: fingerprint,
            expectedEntry: SongLibraryExpectedEntryIdentity(
                songID: expectedSongID,
                scoreFileVersionID: UUID(),
                musicXMLFileName: "score.musicxml"
            ),
            newEntry: SongLibraryNewEntryPayload(
                songID: UUID(),
                displayName: "score",
                musicXMLFileName: "score.musicxml",
                importedAt: .now,
                scoreFileVersionID: UUID()
            )
        )
    }
}

@Test
func recoveryBlocksNewImportWhenAnotherSongOwnsTheTargetFileName() async throws {
    let fixture = try ImportTransactionFixture()
    defer { fixture.remove() }
    try fixture.paths.ensureDirectoriesExist()
    let safeFileName = "owned.musicxml"
    let existing = transactionEntry(name: safeFileName)
    _ = try await fixture.indexStore.appendUserEntry(existing)
    let targetData = Data("existing-target".utf8)
    try targetData.write(to: fixture.paths.scoreFileURL(safeFileName: safeFileName))
    let operationID = UUID()
    try fixture.writeJournal(
        SongLibraryImportJournal(
            operationID: operationID,
            kind: .newImport,
            phase: .targetInstalled,
            safeFileName: safeFileName,
            stagedFingerprint: transactionFingerprint(targetData),
            newEntry: SongLibraryNewEntryPayload(
                songID: UUID(),
                displayName: "owned",
                musicXMLFileName: safeFileName,
                importedAt: Date(timeIntervalSince1970: 1_700_000_500),
                scoreFileVersionID: UUID()
            )
        )
    )

    guard case .blocked = await fixture.service.recoverPendingTransactions() else {
        Issue.record("Expected another song's target identity to block recovery")
        return
    }
    #expect(try await fixture.indexStore.load().entries == [existing])
    #expect(try Data(contentsOf: fixture.paths.scoreFileURL(safeFileName: safeFileName)) == targetData)
}

private final class RecordingDiagnosticsSink: SystemDiagnosticsSinkProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DiagnosticEvent] = []

    var events: [DiagnosticEvent] {
        lock.withLock { storage }
    }

    func record(_ event: DiagnosticEvent) {
        lock.withLock { storage.append(event) }
    }
}

private actor RecordingTransactionDiagnosticsReporter: DiagnosticsReporting {
    private(set) var events: [DiagnosticEvent] = []

    func record(_ event: DiagnosticEvent) -> DiagnosticRecordResult {
        events.append(event)
        return DiagnosticRecordResult(persistedForExport: false)
    }
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
        return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
    }.joined()
    return try TransactionFileFingerprint(byteCount: Int64(data.count), sha256: digest)
}
