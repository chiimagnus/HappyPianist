import CryptoKit
import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func batchStagingPreservesOrderAndBalancesSecurityScope() async throws {
    let security = ImportSecurityScopeSpy(startResult: true)
    let fixture = try ImportTransactionFixture(security: security)
    defer { fixture.remove() }
    let first = try fixture.makeSource(name: "first.musicxml", contents: "first")
    let rejected = try fixture.makeDirectory(name: "folder.xml")
    let second = try fixture.makeSource(name: "second.mxl", contents: "second")

    let result = await fixture.service.stageImports(from: [first, rejected, second])

    #expect(result.blocked == nil)
    #expect(result.items.count == 3)
    guard case let .staged(firstDescriptor) = result.items[0],
          case let .failure(failure) = result.items[1],
          case let .staged(secondDescriptor) = result.items[2]
    else {
        Issue.record("Expected staged/failure/staged order")
        return
    }
    #expect(firstDescriptor.fileName == "first.musicxml")
    #expect(failure.fileName == "folder.xml")
    #expect(secondDescriptor.fileName == "second.mxl")
    #expect(security.startedNames == ["first.musicxml", "folder.xml", "second.mxl"])
    #expect(security.stoppedNames == security.startedNames)
    #expect(await fixture.service.cancel(operationID: firstDescriptor.id))
    #expect(await fixture.service.cancel(operationID: secondDescriptor.id))
}

@Test
func stagingWithoutSecurityScopeStillReadsAndInvalidExtensionNeverStartsAccess() async throws {
    let security = ImportSecurityScopeSpy(startResult: false)
    let fixture = try ImportTransactionFixture(security: security)
    defer { fixture.remove() }
    let valid = try fixture.makeSource(name: "score.XML", contents: "score")
    let invalid = try fixture.makeSource(name: "notes.pdf", contents: "notes")

    let result = await fixture.service.stageImports(from: [invalid, valid])

    #expect(result.blocked == nil)
    #expect(security.startedNames == ["score.XML"])
    #expect(security.stoppedNames.isEmpty)
    guard case let .staged(descriptor)? = result.items.last else {
        Issue.record("Expected valid file to stage without security scope")
        return
    }
    #expect(await fixture.service.cancel(operationID: descriptor.id))
}

@Test
func stagingRejectsSymbolicLinkAndRecordsStreamingFingerprint() async throws {
    let fixture = try ImportTransactionFixture()
    defer { fixture.remove() }
    let source = try fixture.makeSource(name: "score.musicxml", contents: "streamed-score")
    let link = fixture.externalURL.appending(path: "link.musicxml")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)

    let result = await fixture.service.stageImports(from: [link, source])

    guard case .failure = result.items[0],
          case let .staged(descriptor) = result.items[1]
    else {
        Issue.record("Expected symlink rejection and regular-file staging")
        return
    }
    let journal = try fixture.journal(operationID: descriptor.id)
    let expectedFingerprint = try fingerprint(Data("streamed-score".utf8))
    #expect(journal.stagedFingerprint == expectedFingerprint)
    let stagedURL = try fixture.paths.transactionStageFileURL(
        operationID: descriptor.id,
        safeFileName: "score.musicxml"
    )
    #expect(try Data(contentsOf: stagedURL) == Data("streamed-score".utf8))
    #expect(await fixture.service.cancel(operationID: descriptor.id))
}

@Test
func noConflictImportCommitsOriginalNameAndCleansTransaction() async throws {
    let importedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let fixture = try ImportTransactionFixture(now: importedAt)
    defer { fixture.remove() }
    let source = try fixture.makeSource(name: "Original Name.musicxml", contents: "score")
    let staged = await fixture.service.stageImports(from: [source])
    guard case let .staged(descriptor)? = staged.items.first else {
        Issue.record("Expected staged import")
        return
    }
    let stagedURL = try fixture.paths.transactionStageFileURL(
        operationID: descriptor.id,
        safeFileName: descriptor.fileName
    )
    #expect(FileManager.default.fileExists(atPath: stagedURL.path(percentEncoded: false)))

    let result = await fixture.service.process(operationID: descriptor.id)

    guard case let .committed(index, entry) = result else {
        Issue.record("Expected committed import, got \(String(describing: result))")
        return
    }
    #expect(entry.displayName == "Original Name")
    #expect(entry.musicXMLFileName == "Original Name.musicxml")
    #expect(entry.importedAt == importedAt)
    #expect(entry.scoreFileVersionID != nil)
    #expect(index.entries == [entry])
    #expect(
        FileManager.default.fileExists(
            atPath: try fixture.paths.scoreFileURL(safeFileName: "Original Name.musicxml").path(percentEncoded: false)
        )
    )
    #expect(
        try FileManager.default.contentsOfDirectory(
            at: fixture.paths.transactionsDirectoryURL(),
            includingPropertiesForKeys: nil
        ).isEmpty
    )
}

@Test
func conflictPublishesPendingWithoutChangingTargetOrIndex() async throws {
    let fixture = try ImportTransactionFixture()
    defer { fixture.remove() }
    try fixture.paths.ensureDirectoriesExist()
    let existing = makeImportEntry(fileName: "same.musicxml")
    _ = try await fixture.indexStore.appendUserEntry(existing)
    let target = try fixture.paths.scoreFileURL(safeFileName: "same.musicxml")
    try Data("old".utf8).write(to: target)
    let source = try fixture.makeSource(name: "same.musicxml", contents: "new")
    let staged = await fixture.service.stageImports(from: [source])
    guard case let .staged(descriptor)? = staged.items.first else {
        Issue.record("Expected staged conflict")
        return
    }

    let result = await fixture.service.process(operationID: descriptor.id)

    guard case let .requiresConfirmation(pending) = result else {
        Issue.record("Expected pending conflict")
        return
    }
    #expect(pending.id == descriptor.id)
    #expect(pending.conflict == .indexedTarget(entry: existing))
    #expect(try Data(contentsOf: target) == Data("old".utf8))
    #expect(try await fixture.indexStore.load().entries == [existing])
    #expect(try fixture.journal(operationID: descriptor.id).phase == .staged)
    #expect(await fixture.service.cancel(operationID: descriptor.id))
}

@Test
func confirmedIndexedReplacementPreservesNonScoreFieldsAndOriginalPosition() async throws {
    let importedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let fixture = try ImportTransactionFixture(now: importedAt)
    defer { fixture.remove() }
    try fixture.paths.ensureDirectoriesExist()
    let first = makeImportEntry(fileName: "first.musicxml")
    let replaced = SongLibraryEntry(
        id: UUID(),
        displayName: "Custom Display",
        musicXMLFileName: "same.musicxml",
        scoreFileVersionID: UUID(),
        importedAt: .distantPast,
        audioFileName: "listen.m4a"
    )
    _ = try await fixture.indexStore.appendUserEntry(first)
    _ = try await fixture.indexStore.appendUserEntry(replaced)
    _ = try await fixture.indexStore.setLastSelectedEntryID(replaced.id)
    let target = try fixture.paths.scoreFileURL(safeFileName: "same.musicxml")
    try Data("old".utf8).write(to: target)
    let source = try fixture.makeSource(name: "same.musicxml", contents: "new")
    let staged = await fixture.service.stageImports(from: [source])
    guard case let .staged(descriptor)? = staged.items.first else {
        Issue.record("Expected staged replacement")
        return
    }
    guard case .requiresConfirmation = await fixture.service.process(operationID: descriptor.id) else {
        Issue.record("Expected indexed conflict")
        return
    }

    let result = await fixture.service.confirm(operationID: descriptor.id)

    guard case let .committed(index, updated) = result else {
        Issue.record("Expected committed replacement, got \(result)")
        return
    }
    #expect(index.entries.map(\.id) == [first.id, replaced.id])
    #expect(index.lastSelectedEntryID == replaced.id)
    #expect(updated.id == replaced.id)
    #expect(updated.displayName == replaced.displayName)
    #expect(updated.audioFileName == replaced.audioFileName)
    #expect(updated.importedAt == importedAt)
    #expect(updated.scoreFileVersionID != replaced.scoreFileVersionID)
    #expect(try Data(contentsOf: target) == Data("new".utf8))
}

@Test
func confirmedMissingTargetRepairKeepsEntryIdentityAndInstallsOriginalName() async throws {
    let fixture = try ImportTransactionFixture()
    defer { fixture.remove() }
    try fixture.paths.ensureDirectoriesExist()
    let entry = SongLibraryEntry(
        id: UUID(),
        displayName: "Keep Me",
        musicXMLFileName: "missing.musicxml",
        scoreFileVersionID: UUID(),
        importedAt: .distantPast,
        audioFileName: "keep.mp3"
    )
    _ = try await fixture.indexStore.appendUserEntry(entry)
    let source = try fixture.makeSource(name: "missing.musicxml", contents: "repair")
    let staged = await fixture.service.stageImports(from: [source])
    guard case let .staged(descriptor)? = staged.items.first else {
        Issue.record("Expected staged repair")
        return
    }
    guard case .requiresConfirmation = await fixture.service.process(operationID: descriptor.id) else {
        Issue.record("Expected missing-target conflict")
        return
    }

    let result = await fixture.service.confirm(operationID: descriptor.id)

    guard case let .committed(_, updated) = result else {
        Issue.record("Expected committed repair, got \(result)")
        return
    }
    #expect(updated.id == entry.id)
    #expect(updated.displayName == entry.displayName)
    #expect(updated.audioFileName == entry.audioFileName)
    #expect(updated.scoreFileVersionID != entry.scoreFileVersionID)
    #expect(
        try Data(contentsOf: fixture.paths.scoreFileURL(safeFileName: "missing.musicxml"))
            == Data("repair".utf8)
    )
}

@Test
func confirmedFilesystemOrphanReplacesOldBytesAndCreatesNewEntry() async throws {
    let fixture = try ImportTransactionFixture()
    defer { fixture.remove() }
    try fixture.paths.ensureDirectoriesExist()
    let target = try fixture.paths.scoreFileURL(safeFileName: "orphan.musicxml")
    try Data("orphan-old".utf8).write(to: target)
    let source = try fixture.makeSource(name: "orphan.musicxml", contents: "adopted-new")
    let staged = await fixture.service.stageImports(from: [source])
    guard case let .staged(descriptor)? = staged.items.first else {
        Issue.record("Expected staged orphan adoption")
        return
    }
    guard case .requiresConfirmation = await fixture.service.process(operationID: descriptor.id) else {
        Issue.record("Expected orphan conflict")
        return
    }

    let result = await fixture.service.confirm(operationID: descriptor.id)

    guard case let .committed(index, entry) = result else {
        Issue.record("Expected committed orphan adoption, got \(result)")
        return
    }
    #expect(index.entries == [entry])
    #expect(entry.displayName == "orphan")
    #expect(entry.musicXMLFileName == "orphan.musicxml")
    #expect(entry.scoreFileVersionID != nil)
    #expect(try Data(contentsOf: target) == Data("adopted-new".utf8))
}

@Test
func confirmationReclassifiesTargetThatAppearedWhileWaiting() async throws {
    let fixture = try ImportTransactionFixture()
    defer { fixture.remove() }
    try fixture.paths.ensureDirectoriesExist()
    let entry = makeImportEntry(fileName: "appeared.musicxml")
    _ = try await fixture.indexStore.appendUserEntry(entry)
    let source = try fixture.makeSource(name: "appeared.musicxml", contents: "new")
    let staged = await fixture.service.stageImports(from: [source])
    guard case let .staged(descriptor)? = staged.items.first else {
        Issue.record("Expected staged import")
        return
    }
    guard case let .requiresConfirmation(pending) = await fixture.service.process(operationID: descriptor.id),
          case .indexedMissingTarget = pending.conflict
    else {
        Issue.record("Expected missing-target conflict")
        return
    }
    let target = try fixture.paths.scoreFileURL(safeFileName: "appeared.musicxml")
    try Data("appeared-old".utf8).write(to: target)

    let result = await fixture.service.confirm(operationID: descriptor.id)

    guard case let .committed(_, updated) = result else {
        Issue.record("Expected reclassified replacement, got \(result)")
        return
    }
    #expect(updated.id == entry.id)
    #expect(try Data(contentsOf: target) == Data("new".utf8))
}

@Test
func replacementCASRaceRestoresOldTargetAndReturnsUpdatedPendingConflict() async throws {
    let original = makeImportEntry(fileName: "race.musicxml")
    let indexStore = RacingImportIndexStore(index: SongLibraryIndex(entries: [original]))
    let fixture = try ImportTransactionFixture(indexStore: indexStore)
    defer { fixture.remove() }
    try fixture.paths.ensureDirectoriesExist()
    let target = try fixture.paths.scoreFileURL(safeFileName: "race.musicxml")
    try Data("old".utf8).write(to: target)
    let source = try fixture.makeSource(name: "race.musicxml", contents: "new")
    let staged = await fixture.service.stageImports(from: [source])
    guard case let .staged(descriptor)? = staged.items.first else {
        Issue.record("Expected staged import")
        return
    }
    guard case .requiresConfirmation = await fixture.service.process(operationID: descriptor.id) else {
        Issue.record("Expected initial conflict")
        return
    }

    let result = await fixture.service.confirm(operationID: descriptor.id)

    guard case let .requiresConfirmation(pending) = result,
          case let .indexedTarget(updatedEntry) = pending.conflict
    else {
        Issue.record("Expected updated pending conflict after CAS race, got \(result)")
        return
    }
    #expect(updatedEntry.id == original.id)
    #expect(updatedEntry.scoreFileVersionID != original.scoreFileVersionID)
    #expect(try Data(contentsOf: target) == Data("old".utf8))
    #expect(try fixture.journal(operationID: descriptor.id).phase == .staged)
    #expect(await fixture.service.cancel(operationID: descriptor.id))
}

@Test
func ambiguousConflictBlocksAndCleansOnlyStagedOperation() async throws {
    let fixture = try ImportTransactionFixture()
    defer { fixture.remove() }
    try fixture.paths.ensureDirectoriesExist()
    let first = makeImportEntry(fileName: "same.musicxml")
    var second = makeImportEntry(fileName: "other.musicxml")
    second.musicXMLFileName = "same.musicxml"
    _ = try await fixture.indexStore.appendUserEntry(first)
    _ = try await fixture.indexStore.appendUserEntry(second)
    let target = try fixture.paths.scoreFileURL(safeFileName: "same.musicxml")
    try Data("old".utf8).write(to: target)
    let source = try fixture.makeSource(name: "same.musicxml", contents: "new")
    let staged = await fixture.service.stageImports(from: [source])
    guard case let .staged(descriptor)? = staged.items.first else {
        Issue.record("Expected staged import")
        return
    }

    let result = await fixture.service.process(operationID: descriptor.id)

    guard case .blocked = result else {
        Issue.record("Expected ambiguous block")
        return
    }
    #expect(try Data(contentsOf: target) == Data("old".utf8))
    #expect(
        FileManager.default.fileExists(
            atPath: try fixture.paths.transactionOperationDirectoryURL(operationID: descriptor.id).path(percentEncoded: false)
        ) == false
    )
}

@Test
func indexAppendFailureRollsTargetBackAndLeavesOldLibraryUnchanged() async throws {
    let indexStore = FailingImportIndexStore()
    let fixture = try ImportTransactionFixture(indexStore: indexStore)
    defer { fixture.remove() }
    let source = try fixture.makeSource(name: "rollback.musicxml", contents: "score")
    let staged = await fixture.service.stageImports(from: [source])
    guard case let .staged(descriptor)? = staged.items.first else {
        Issue.record("Expected staged import")
        return
    }

    let result = await fixture.service.process(operationID: descriptor.id)

    guard case .itemFailure = result else {
        Issue.record("Expected safe item failure")
        return
    }
    #expect(
        FileManager.default.fileExists(
            atPath: try fixture.paths.scoreFileURL(safeFileName: "rollback.musicxml").path(percentEncoded: false)
        ) == false
    )
    #expect(await indexStore.load() == .empty)
    #expect(
        FileManager.default.fileExists(
            atPath: try fixture.paths.transactionOperationDirectoryURL(operationID: descriptor.id).path(percentEncoded: false)
        ) == false
    )
}

@Test
func bootstrapRecoveryRollsForwardStagedNewImportAndCommitsIndex() async throws {
    let fixture = try ImportTransactionFixture()
    defer { fixture.remove() }
    try fixture.paths.ensureDirectoriesExist()
    let operationID = UUID()
    let data = Data("recover".utf8)
    let stagedURL = try fixture.paths.transactionStageFileURL(
        operationID: operationID,
        safeFileName: "recover.musicxml"
    )
    try FileManager.default.createDirectory(
        at: stagedURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: stagedURL)
    let payload = SongLibraryNewEntryPayload(
        songID: UUID(),
        displayName: "recover",
        musicXMLFileName: "recover.musicxml",
        importedAt: Date(timeIntervalSince1970: 1_700_000_000),
        scoreFileVersionID: UUID()
    )
    let journal = try SongLibraryImportJournal(
        operationID: operationID,
        kind: .newImport,
        phase: .targetInstalled,
        safeFileName: "recover.musicxml",
        stagedFingerprint: fingerprint(data),
        newEntry: payload
    )
    try fixture.writeJournal(journal)

    #expect(await fixture.service.recoverPendingTransactions() == .recovered)
    do {
        let recoveredIndex = try await fixture.indexStore.load()
        #expect(
            recoveredIndex.entries == [payload.entry],
            "Recovered \(recoveredIndex.entries) in \(fixture.documentsURL.lastPathComponent)"
        )
    } catch {
        Issue.record(
            "Failed to load recovered index in \(fixture.documentsURL.lastPathComponent): \(error)"
        )
    }
    #expect(
        try Data(
            contentsOf: fixture.paths.scoreFileURL(safeFileName: "recover.musicxml")
        ) == data
    )
    #expect(
        FileManager.default.fileExists(
            atPath: try fixture.paths.transactionOperationDirectoryURL(operationID: operationID).path(percentEncoded: false)
        ) == false
    )
}

@Test
func recoveryCommitsInstalledReplacementAndMissingRepairIdempotently() async throws {
    for kind in [SongLibraryImportOperationKind.indexedReplace, .missingTargetRepair] {
        let fixture = try ImportTransactionFixture()
        defer { fixture.remove() }
        try fixture.paths.ensureDirectoriesExist()
        let oldEntry = SongLibraryEntry(
            id: UUID(),
            displayName: "Preserved",
            musicXMLFileName: "recover-replace.musicxml",
            scoreFileVersionID: UUID(),
            importedAt: .distantPast,
            audioFileName: "preserved.m4a"
        )
        _ = try await fixture.indexStore.appendUserEntry(oldEntry)
        let newData = Data("new-installed".utf8)
        let oldData = Data("old-backup".utf8)
        let operationID = UUID()
        let target = try fixture.paths.scoreFileURL(safeFileName: oldEntry.musicXMLFileName)
        try newData.write(to: target)
        let backupFingerprint: TransactionFileFingerprint?
        if kind == .indexedReplace {
            let backup = try fixture.paths.transactionBackupFileURL(
                operationID: operationID,
                safeFileName: oldEntry.musicXMLFileName
            )
            try fixture.writeFile(oldData, to: backup)
            backupFingerprint = try fingerprint(oldData)
        } else {
            backupFingerprint = nil
        }
        let payload = SongLibraryNewEntryPayload(
            songID: oldEntry.id,
            displayName: oldEntry.displayName,
            musicXMLFileName: oldEntry.musicXMLFileName,
            importedAt: Date(timeIntervalSince1970: 1_700_000_200),
            scoreFileVersionID: UUID()
        )
        try fixture.writeJournal(
            SongLibraryImportJournal(
                operationID: operationID,
                kind: kind,
                phase: .targetInstalled,
                safeFileName: oldEntry.musicXMLFileName,
                stagedFingerprint: fingerprint(newData),
                backupFingerprint: backupFingerprint,
                expectedEntry: SongLibraryExpectedEntryIdentity(
                    songID: oldEntry.id,
                    scoreFileVersionID: oldEntry.scoreFileVersionID,
                    musicXMLFileName: oldEntry.musicXMLFileName
                ),
                newEntry: payload
            )
        )

        #expect(await fixture.service.recoverPendingTransactions() == .recovered)
        #expect(await fixture.service.recoverPendingTransactions() == .recovered)
        let recovered = try await fixture.indexStore.load().entries[0]
        #expect(recovered.id == oldEntry.id)
        #expect(recovered.displayName == oldEntry.displayName)
        #expect(recovered.audioFileName == oldEntry.audioFileName)
        #expect(recovered.scoreFileVersionID == payload.scoreFileVersionID)
        #expect(try Data(contentsOf: target) == newData)
    }
}

@Test
func recoveryRollsForwardOrphanAdoptionAndBlocksTamperedTarget() async throws {
    let fixture = try ImportTransactionFixture()
    defer { fixture.remove() }
    try fixture.paths.ensureDirectoriesExist()
    let operationID = UUID()
    let fileName = "recover-orphan.musicxml"
    let stagedData = Data("new-orphan".utf8)
    let backupData = Data("old-orphan".utf8)
    try fixture.writeFile(
        stagedData,
        to: fixture.paths.transactionStageFileURL(
            operationID: operationID,
            safeFileName: fileName
        )
    )
    try fixture.writeFile(
        backupData,
        to: fixture.paths.transactionBackupFileURL(
            operationID: operationID,
            safeFileName: fileName
        )
    )
    let payload = SongLibraryNewEntryPayload(
        songID: UUID(),
        displayName: "recover-orphan",
        musicXMLFileName: fileName,
        importedAt: Date(timeIntervalSince1970: 1_700_000_300),
        scoreFileVersionID: UUID()
    )
    try fixture.writeJournal(
        SongLibraryImportJournal(
            operationID: operationID,
            kind: .orphanAdopt,
            phase: .backupMoved,
            safeFileName: fileName,
            stagedFingerprint: fingerprint(stagedData),
            backupFingerprint: fingerprint(backupData),
            newEntry: payload
        )
    )

    #expect(await fixture.service.recoverPendingTransactions() == .recovered)
    #expect(await fixture.service.recoverPendingTransactions() == .recovered)
    #expect(try await fixture.indexStore.load().entries == [payload.entry])
    #expect(
        try Data(contentsOf: fixture.paths.scoreFileURL(safeFileName: fileName)) == stagedData
    )

    let tamperedFixture = try ImportTransactionFixture()
    defer { tamperedFixture.remove() }
    try tamperedFixture.paths.ensureDirectoriesExist()
    let tamperedID = UUID()
    let tamperedPayload = SongLibraryNewEntryPayload(
        songID: UUID(),
        displayName: "tampered",
        musicXMLFileName: "tampered.musicxml",
        importedAt: Date(timeIntervalSince1970: 1_700_000_400),
        scoreFileVersionID: UUID()
    )
    try Data("external-change".utf8).write(
        to: tamperedFixture.paths.scoreFileURL(safeFileName: "tampered.musicxml")
    )
    try tamperedFixture.writeJournal(
        SongLibraryImportJournal(
            operationID: tamperedID,
            kind: .newImport,
            phase: .targetInstalled,
            safeFileName: "tampered.musicxml",
            stagedFingerprint: fingerprint(Data("expected".utf8)),
            newEntry: tamperedPayload
        )
    )

    guard case .blocked = await tamperedFixture.service.recoverPendingTransactions() else {
        Issue.record("Expected tampered target to block recovery")
        return
    }
    #expect(
        try Data(contentsOf: tamperedFixture.paths.scoreFileURL(safeFileName: "tampered.musicxml"))
            == Data("external-change".utf8)
    )
}

@MainActor
@Test
func importQueueCancelsConflictThenCommitsNextAndGatesPracticeAndDelete() async {
    let existing = makeImportEntry(fileName: "existing.musicxml")
    let pendingID = UUID()
    let committedID = UUID()
    let committed = makeImportEntry(fileName: "committed.musicxml")
    let finalIndex = SongLibraryIndex(entries: [existing, committed], lastSelectedEntryID: existing.id)
    let service = QueueImportTransactionService(
        items: [
            .staged(SongLibraryStagedImport(id: pendingID, fileName: "conflict.musicxml")),
            .staged(SongLibraryStagedImport(id: committedID, fileName: "committed.musicxml")),
        ],
        processResults: [
            pendingID: .requiresConfirmation(
                SongLibraryPendingImport(
                    id: pendingID,
                    fileName: "conflict.musicxml",
                    conflict: .filesystemOrphan
                )
            ),
            committedID: .committed(index: finalIndex, entry: committed),
        ]
    )
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [existing], lastSelectedEntryID: existing.id),
        importTransactionService: service
    )

    await viewModel.importMusicXML(from: [
        URL(fileURLWithPath: "/tmp/conflict.musicxml"),
        URL(fileURLWithPath: "/tmp/committed.musicxml"),
    ])
    guard case .awaitingConfirmation = viewModel.importState else {
        Issue.record("Expected pending conflict")
        return
    }
    var started = false
    viewModel.startPractice(entryID: existing.id) { _ in started = true }
    await viewModel.deleteEntry(entryID: existing.id)
    #expect(started == false)
    #expect(viewModel.index.entries == [existing])

    await viewModel.cancelPendingImport(operationID: pendingID)
    await viewModel.cancelPendingImport(operationID: pendingID)

    #expect(viewModel.importState == .idle)
    #expect(viewModel.index == finalIndex)
    #expect(await service.cancelledOperationIDs == [pendingID])
    #expect(await service.processedOperationIDs == [pendingID, committedID])
}

@MainActor
@Test
func importQueueConfirmsCurrentConflictThenContinuesWithoutSecondStateMachine() async {
    let operationID = UUID()
    let committed = makeImportEntry(fileName: "confirmed.musicxml")
    let finalIndex = SongLibraryIndex(entries: [committed])
    let service = QueueImportTransactionService(
        items: [.staged(SongLibraryStagedImport(id: operationID, fileName: "confirmed.musicxml"))],
        processResults: [
            operationID: .requiresConfirmation(
                SongLibraryPendingImport(
                    id: operationID,
                    fileName: "confirmed.musicxml",
                    conflict: .filesystemOrphan
                )
            )
        ],
        confirmResults: [
            operationID: .committed(index: finalIndex, entry: committed)
        ]
    )
    let viewModel = SongLibraryViewModelTestHarness.make(importTransactionService: service)
    await viewModel.importMusicXML(
        from: [URL(fileURLWithPath: "/tmp/confirmed.musicxml")]
    )
    guard case .awaitingConfirmation = viewModel.importState else {
        Issue.record("Expected pending conflict")
        return
    }

    await viewModel.confirmPendingImport(operationID: operationID)
    await viewModel.confirmPendingImport(operationID: operationID)

    #expect(viewModel.importState == .idle)
    #expect(viewModel.index == finalIndex)
    #expect(await service.confirmedOperationIDs == [operationID])
}

@MainActor
@Test
func cancellingDuringStagingDiscardsReturnedOperationsByGeneration() async {
    let operationID = UUID()
    let service = QueueImportTransactionService(
        items: [.staged(SongLibraryStagedImport(id: operationID, fileName: "late.musicxml"))],
        stageDelay: .milliseconds(50)
    )
    let viewModel = SongLibraryViewModelTestHarness.make(importTransactionService: service)
    let importTask = Task {
        await viewModel.importMusicXML(from: [URL(fileURLWithPath: "/tmp/late.musicxml")])
    }
    await Task.yield()

    await viewModel.cancelAllImports()
    await importTask.value

    #expect(viewModel.importState == .idle)
    #expect(await service.cancelledOperationIDs == [operationID])
    #expect(await service.processedOperationIDs.isEmpty)
}

@MainActor
@Test
func cancellingAllPendingImportsCleansCurrentAndRemainingOperations() async {
    let firstID = UUID()
    let secondID = UUID()
    let service = QueueImportTransactionService(
        items: [
            .staged(SongLibraryStagedImport(id: firstID, fileName: "first.musicxml")),
            .staged(SongLibraryStagedImport(id: secondID, fileName: "second.musicxml")),
        ],
        processResults: [
            firstID: .requiresConfirmation(
                SongLibraryPendingImport(
                    id: firstID,
                    fileName: "first.musicxml",
                    conflict: .filesystemOrphan
                )
            )
        ]
    )
    let viewModel = SongLibraryViewModelTestHarness.make(importTransactionService: service)
    await viewModel.importMusicXML(from: [
        URL(fileURLWithPath: "/tmp/first.musicxml"),
        URL(fileURLWithPath: "/tmp/second.musicxml"),
    ])

    await viewModel.cancelAllImports()

    #expect(viewModel.importState == .idle)
    #expect(await service.cancelledOperationIDs == [firstID, secondID])
    #expect(await service.processedOperationIDs == [firstID])
}

@MainActor
@Test
func itemFailureWaitsForAcknowledgementThenContinuesQueue() async {
    let committedID = UUID()
    let committed = makeImportEntry(fileName: "good.musicxml")
    let finalIndex = SongLibraryIndex(entries: [committed], lastSelectedEntryID: nil)
    let service = QueueImportTransactionService(
        items: [
            .failure(
                SongLibraryImportItemFailure(
                    fileName: "bad.pdf",
                    message: "文件名或曲谱格式不受支持。"
                )
            ),
            .staged(SongLibraryStagedImport(id: committedID, fileName: "good.musicxml")),
        ],
        processResults: [
            committedID: .committed(index: finalIndex, entry: committed)
        ]
    )
    let viewModel = SongLibraryViewModelTestHarness.make(importTransactionService: service)
    await viewModel.importMusicXML(from: [
        URL(fileURLWithPath: "/tmp/bad.pdf"),
        URL(fileURLWithPath: "/tmp/good.musicxml"),
    ])
    guard case .itemFailure = viewModel.importState else {
        Issue.record("Expected item failure pause")
        return
    }

    await viewModel.continueAfterImportFailure()

    #expect(viewModel.importState == .idle)
    #expect(viewModel.index == finalIndex)
    #expect(await service.processedOperationIDs == [committedID])
}

struct ImportTransactionFixture {
    let documentsURL: URL
    let externalURL: URL
    let paths: SongLibraryPaths
    let indexStore: any SongLibraryImportIndexStoreProtocol
    let service: SongLibraryImportTransactionService

    init(
        indexStore suppliedIndexStore: (any SongLibraryImportIndexStoreProtocol)? = nil,
        security: ImportSecurityScopeSpy = ImportSecurityScopeSpy(startResult: false),
        now: Date = Date(timeIntervalSince1970: 1_700_000_000),
        diagnostics: any DiagnosticsReporting = ImportTransactionDiagnosticsReporter()
    ) throws {
        documentsURL = FileManager.default.temporaryDirectory.appending(
            path: "SongLibraryImportTransactionTests-docs-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        externalURL = FileManager.default.temporaryDirectory.appending(
            path: "SongLibraryImportTransactionTests-external-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalURL, withIntermediateDirectories: true)
        paths = SongLibraryPaths(
            fileManager: ImportTransactionDocumentsFileManager(documentsURL: documentsURL)
        )
        let resolvedIndexStore: any SongLibraryImportIndexStoreProtocol = suppliedIndexStore
            ?? SongLibraryIndexStore(
                fileManager: ImportTransactionDocumentsFileManager(documentsURL: documentsURL),
                paths: SongLibraryPaths(
                    fileManager: ImportTransactionDocumentsFileManager(documentsURL: documentsURL)
                )
            )
        indexStore = resolvedIndexStore
        service = SongLibraryImportTransactionService(
            indexStore: resolvedIndexStore,
            paths: SongLibraryPaths(
                fileManager: ImportTransactionDocumentsFileManager(documentsURL: documentsURL)
            ),
            fileManager: ImportTransactionDocumentsFileManager(documentsURL: documentsURL),
            now: { now },
            diagnostics: diagnostics,
            securityScopedResourceAccessor: security
        )
    }

    func makeSource(name: String, contents: String) throws -> URL {
        let url = externalURL.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func makeDirectory(name: String) throws -> URL {
        let url = externalURL.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func journal(operationID: UUID) throws -> SongLibraryImportJournal {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return try decoder.decode(
            SongLibraryImportJournal.self,
            from: Data(contentsOf: paths.transactionJournalFileURL(operationID: operationID))
        )
    }

    func writeJournal(_ journal: SongLibraryImportJournal) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        let journalURL = try paths.transactionJournalFileURL(operationID: journal.operationID)
        try FileManager.default.createDirectory(
            at: journalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(journal).write(
            to: journalURL,
            options: .atomic
        )
    }

    func writeFile(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: documentsURL)
        try? FileManager.default.removeItem(at: externalURL)
    }
}

final class ImportTransactionDocumentsFileManager: FileManager {
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

final class ImportSecurityScopeSpy: SecurityScopedResourceAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private let startResult: Bool
    private var started: [String] = []
    private var stopped: [String] = []

    init(startResult: Bool) {
        self.startResult = startResult
    }

    var startedNames: [String] { lock.withLock { started } }
    var stoppedNames: [String] { lock.withLock { stopped } }

    func startAccessing(_ url: URL) -> Bool {
        lock.withLock { started.append(url.lastPathComponent) }
        return startResult
    }

    func stopAccessing(_ url: URL) {
        lock.withLock { stopped.append(url.lastPathComponent) }
    }
}

actor ImportTransactionDiagnosticsReporter: DiagnosticsReporting {
    func record(_: DiagnosticEvent) -> DiagnosticRecordResult {
        DiagnosticRecordResult(persistedForExport: false)
    }
}

private actor FailingImportIndexStore: SongLibraryImportIndexStoreProtocol {
    func load() -> SongLibraryIndex { .empty }
    func setLastSelectedEntryID(_: UUID?) -> SongLibraryIndex { .empty }
    func appendUserEntry(_: SongLibraryEntry) throws -> SongLibraryIndex {
        throw CocoaError(.fileWriteUnknown)
    }
    func replaceUserScore(
        expectedSongID _: UUID,
        expectedScoreFileVersionID _: UUID?,
        expectedMusicXMLFileName _: String,
        with _: SongLibraryScoreReplacement
    ) -> SongLibraryScoreReplacementResult {
        .conflict(index: .empty, matchingEntries: [])
    }
    func removeUserEntry(
        id _: UUID,
        fallbackLastSelectedEntryID _: UUID?
    ) -> SongLibraryEntryMutationResult { .notFound(index: .empty) }
    func updateAudioFileName(
        entryID _: UUID,
        expectedCurrentFileName _: String?,
        newFileName _: String?
    ) -> SongLibraryEntryMutationResult { .notFound(index: .empty) }
}

private actor RacingImportIndexStore: SongLibraryImportIndexStoreProtocol {
    private var index: SongLibraryIndex

    init(index: SongLibraryIndex) {
        self.index = index
    }

    func load() -> SongLibraryIndex { index }

    func setLastSelectedEntryID(_ entryID: UUID?) -> SongLibraryIndex {
        index.lastSelectedEntryID = entryID
        return index
    }

    func appendUserEntry(_ entry: SongLibraryEntry) -> SongLibraryIndex {
        index.entries.append(entry)
        return index
    }

    func replaceUserScore(
        expectedSongID: UUID,
        expectedScoreFileVersionID _: UUID?,
        expectedMusicXMLFileName _: String,
        with _: SongLibraryScoreReplacement
    ) -> SongLibraryScoreReplacementResult {
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == expectedSongID }) else {
            return .conflict(index: index, matchingEntries: [])
        }
        index.entries[entryIndex].scoreFileVersionID = UUID()
        return .conflict(index: index, matchingEntries: [index.entries[entryIndex]])
    }

    func removeUserEntry(
        id _: UUID,
        fallbackLastSelectedEntryID _: UUID?
    ) -> SongLibraryEntryMutationResult { .notFound(index: index) }

    func updateAudioFileName(
        entryID _: UUID,
        expectedCurrentFileName _: String?,
        newFileName _: String?
    ) -> SongLibraryEntryMutationResult { .notFound(index: index) }
}

private actor QueueImportTransactionService: SongLibraryImportTransactionServicing {
    let items: [SongLibraryImportBatchItem]
    let processResults: [UUID: SongLibraryImportProcessResult]
    let confirmResults: [UUID: SongLibraryImportProcessResult]
    let stageDelay: Duration
    private(set) var cancelledOperationIDs: [UUID] = []
    private(set) var processedOperationIDs: [UUID] = []
    private(set) var confirmedOperationIDs: [UUID] = []

    init(
        items: [SongLibraryImportBatchItem],
        processResults: [UUID: SongLibraryImportProcessResult] = [:],
        confirmResults: [UUID: SongLibraryImportProcessResult] = [:],
        stageDelay: Duration = .zero
    ) {
        self.items = items
        self.processResults = processResults
        self.confirmResults = confirmResults
        self.stageDelay = stageDelay
    }

    func recoverPendingTransactions() -> SongLibraryTransactionRecoveryResult { .recovered }

    func stageImports(from _: [URL]) async -> SongLibraryImportBatchStageResult {
        if stageDelay != .zero {
            try? await Task.sleep(for: stageDelay)
        }
        return SongLibraryImportBatchStageResult(items: items, blocked: nil)
    }

    func process(operationID: UUID) -> SongLibraryImportProcessResult {
        processedOperationIDs.append(operationID)
        return processResults[operationID]
            ?? .blocked(SongLibraryBlockedImport(operationID: operationID, message: "missing result"))
    }

    func confirm(operationID: UUID) -> SongLibraryImportProcessResult {
        confirmedOperationIDs.append(operationID)
        return confirmResults[operationID]
            ?? processResults[operationID]
            ?? .blocked(SongLibraryBlockedImport(operationID: operationID, message: "missing result"))
    }

    func cancel(operationID: UUID) -> Bool {
        guard cancelledOperationIDs.contains(operationID) == false else { return true }
        cancelledOperationIDs.append(operationID)
        return true
    }
}

private func makeImportEntry(fileName: String) -> SongLibraryEntry {
    SongLibraryEntry(
        id: UUID(),
        displayName: URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent,
        musicXMLFileName: fileName,
        scoreFileVersionID: UUID(),
        importedAt: .distantPast,
        audioFileName: nil
    )
}

private func fingerprint(_ data: Data) throws -> TransactionFileFingerprint {
    let digest = SHA256.hash(data: data).map { byte in
        let digits = Array("0123456789abcdef")
        return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0f)]])
    }.joined()
    return try TransactionFileFingerprint(byteCount: Int64(data.count), sha256: digest)
}
