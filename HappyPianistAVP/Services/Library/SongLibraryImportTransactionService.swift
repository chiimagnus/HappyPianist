import CryptoKit
import Foundation

protocol SongLibraryImportTransactionRecovering: Actor {
    func recoverPendingTransactions() async -> SongLibraryTransactionRecoveryResult
}

protocol SongLibraryImportTransactionServicing: SongLibraryImportTransactionRecovering {
    func stageImports(from selectedURLs: [URL]) async -> SongLibraryImportBatchStageResult
    func process(operationID: UUID) async -> SongLibraryImportProcessResult
    func confirm(operationID: UUID) async -> SongLibraryImportProcessResult
    func cancel(operationID: UUID) async -> Bool
}

protocol SecurityScopedResourceAccessing: Sendable {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

struct LiveSecurityScopedResourceAccessor: SecurityScopedResourceAccessing {
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

actor SongLibraryImportTransactionService: SongLibraryImportTransactionServicing {
    private static let supportedScoreExtensions = Set(["xml", "musicxml", "mxl"])

    private let indexStore: any SongLibraryImportIndexStoreProtocol
    private let paths: SongLibraryPaths
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let makeUUID: @Sendable () -> UUID
    private let diagnostics: any DiagnosticsReporting
    private let securityScopedResourceAccessor: any SecurityScopedResourceAccessing

    init(
        indexStore: any SongLibraryImportIndexStoreProtocol,
        paths: SongLibraryPaths? = nil,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { .now },
        makeUUID: @escaping @Sendable () -> UUID = { UUID() },
        diagnostics: any DiagnosticsReporting,
        securityScopedResourceAccessor: any SecurityScopedResourceAccessing = LiveSecurityScopedResourceAccessor()
    ) {
        self.indexStore = indexStore
        self.paths = paths ?? SongLibraryPaths(fileManager: fileManager)
        self.fileManager = fileManager
        self.now = now
        self.makeUUID = makeUUID
        self.diagnostics = diagnostics
        self.securityScopedResourceAccessor = securityScopedResourceAccessor
    }

    func stageImports(from selectedURLs: [URL]) async -> SongLibraryImportBatchStageResult {
        guard selectedURLs.isEmpty == false else {
            return SongLibraryImportBatchStageResult(items: [], blocked: nil)
        }
        do {
            try ensureRecoveryDirectoriesAreSafe()
        } catch {
            return SongLibraryImportBatchStageResult(
                items: [],
                blocked: SongLibraryBlockedImport(
                    operationID: nil,
                    message: "无法准备曲谱导入目录，请修复存储后重试。"
                )
            )
        }

        var items: [SongLibraryImportBatchItem] = []
        var stagedOperationIDs: [UUID] = []
        for sourceURL in selectedURLs {
            if Task.isCancelled {
                await cancelStagedOperations(stagedOperationIDs)
                return cancelledBatch(items: items)
            }
            let sourceFileName = sourceURL.lastPathComponent
            guard isValidSourceFileName(sourceFileName) else {
                items.append(.failure(itemFailure(fileName: sourceFileName, message: "文件名或曲谱格式不受支持。")))
                continue
            }

            let operationID = makeUUID()
            switch await stageOne(
                sourceURL: sourceURL,
                safeFileName: sourceFileName,
                operationID: operationID
            ) {
            case let .staged(descriptor):
                items.append(.staged(descriptor))
                stagedOperationIDs.append(operationID)
            case let .itemFailure(failure):
                items.append(.failure(failure))
            case let .blocked(blocked):
                for stagedOperationID in stagedOperationIDs {
                    _ = await cancel(operationID: stagedOperationID)
                }
                return SongLibraryImportBatchStageResult(items: items, blocked: blocked)
            }
        }
        if Task.isCancelled {
            await cancelStagedOperations(stagedOperationIDs)
            return cancelledBatch(items: items)
        }
        return SongLibraryImportBatchStageResult(items: items, blocked: nil)
    }

    private func cancelStagedOperations(_ operationIDs: [UUID]) async {
        for operationID in operationIDs {
            _ = await cancel(operationID: operationID)
        }
    }

    private func cancelledBatch(items: [SongLibraryImportBatchItem]) -> SongLibraryImportBatchStageResult {
        SongLibraryImportBatchStageResult(
            items: items,
            blocked: SongLibraryBlockedImport(operationID: nil, message: "本批曲谱导入已取消。")
        )
    }

    func process(operationID: UUID) async -> SongLibraryImportProcessResult {
        do {
            let journal = try loadJournal(operationID: operationID)
            guard journal.kind == .unclassified,
                  journal.phase == .staged,
                  journal.stagedFingerprint != nil
            else {
                return .blocked(
                    SongLibraryBlockedImport(
                        operationID: operationID,
                        message: "导入事务状态已变化，请重新导入。"
                    )
                )
            }

            let index = try await indexStore.load()
            let targetFacts = try targetVolumeFacts(safeFileName: journal.safeFileName)
            let conflict = SongLibraryImportConflictClassifier.classify(
                userEntries: index.entries,
                candidateFileName: journal.safeFileName,
                targetFacts: targetFacts
            )
            switch conflict {
            case .none:
                return try await commitNewImport(journal: journal)
            case .indexedTarget, .indexedMissingTarget, .filesystemOrphan:
                return .requiresConfirmation(
                    SongLibraryPendingImport(
                        id: operationID,
                        fileName: journal.safeFileName,
                        conflict: conflict
                    )
                )
            case .ambiguousIndexedTargets:
                return await blockAmbiguous(journal: journal)
            }
        } catch {
            return .blocked(
                SongLibraryBlockedImport(
                    operationID: operationID,
                    message: "无法核对导入事务，请修复存储后重试。"
                )
            )
        }
    }

    func confirm(operationID: UUID) async -> SongLibraryImportProcessResult {
        do {
            let journal = try loadJournal(operationID: operationID)
            guard journal.kind == .unclassified,
                  journal.phase == .staged,
                  journal.stagedFingerprint != nil
            else {
                return .blocked(
                    SongLibraryBlockedImport(
                        operationID: operationID,
                        message: "导入事务状态已变化，请重新导入。"
                    )
                )
            }

            let index = try await indexStore.load()
            let conflict = SongLibraryImportConflictClassifier.classify(
                userEntries: index.entries,
                candidateFileName: journal.safeFileName,
                targetFacts: try targetVolumeFacts(safeFileName: journal.safeFileName)
            )
            switch conflict {
            case .none:
                return try await commitNewImport(journal: journal)
            case let .indexedTarget(entry):
                return await commitIndexedReplacement(journal: journal, entry: entry)
            case let .indexedMissingTarget(entry):
                return await commitMissingTargetRepair(journal: journal, entry: entry)
            case .filesystemOrphan:
                return await commitOrphanAdoption(journal: journal)
            case .ambiguousIndexedTargets:
                return await blockAmbiguous(journal: journal)
            }
        } catch {
            return .blocked(
                SongLibraryBlockedImport(
                    operationID: operationID,
                    message: "无法重新核对导入冲突，请修复存储后重试。"
                )
            )
        }
    }

    private func blockAmbiguous(
        journal: SongLibraryImportJournal
    ) async -> SongLibraryImportProcessResult {
        _ = await diagnostics.record(
            DiagnosticEvent(
                severity: .error,
                code: .libraryImportConflictAmbiguous,
                category: .library,
                stage: "classifyImport",
                summary: "多个曲库条目指向同一导入目标",
                reason: "为避免猜测曲目身份，已阻止该项导入",
                persistence: .systemOnly
            )
        )
        let message = await cancel(operationID: journal.operationID)
            ? "多个曲库条目指向同一目标，已取消该项导入。"
            : "歧义事务无法安全清理。"
        return blockedImport(journal, message: message)
    }

    func cancel(operationID: UUID) async -> Bool {
        do {
            let operationDirectory = try paths.transactionOperationDirectoryURL(operationID: operationID)
            guard fileManager.fileExists(atPath: operationDirectory.path(percentEncoded: false)) else { return true }
            let journal = try loadJournal(operationID: operationID)
            guard journal.kind == .unclassified else { return false }
            let facts = try await recoveryFacts(for: journal)
            guard SongLibraryTransactionRecoveryPlanner.action(journal: journal, facts: facts) == .cleanup else {
                return false
            }
            try removeOperationDirectory(for: journal, facts: facts)
            return true
        } catch {
            _ = await diagnostics.record(
                DiagnosticEvent(
                    severity: .warning,
                    code: .libraryImportCleanupFailed,
                    category: .library,
                    stage: "cancelImport",
                    summary: "无法清理已取消的曲谱导入",
                    reason: "事务文件已保留供下次启动恢复",
                    persistence: .systemOnly
                )
            )
            return false
        }
    }

    private func stageOne(
        sourceURL: URL,
        safeFileName: String,
        operationID: UUID
    ) async -> SongLibraryStageOneResult {
        let preparingJournal: SongLibraryImportJournal
        do {
            let operationDirectory = try paths.transactionOperationDirectoryURL(operationID: operationID)
            try fileManager.createDirectory(at: operationDirectory, withIntermediateDirectories: false)
            preparingJournal = try SongLibraryImportJournal(
                operationID: operationID,
                kind: .unclassified,
                phase: .preparing,
                safeFileName: safeFileName
            )
            try writeJournal(preparingJournal)
            try fileManager.createDirectory(
                at: try paths.transactionPartialStageFileURL(operationID: operationID)
                    .deletingLastPathComponent(),
                withIntermediateDirectories: false
            )
        } catch {
            await discardFailedStage(operationID: operationID)
            return .blocked(
                SongLibraryBlockedImport(
                    operationID: operationID,
                    message: "无法记录曲谱导入事务，已停止本批导入。"
                )
            )
        }

        let hasScopedAccess = securityScopedResourceAccessor.startAccessing(sourceURL)
        defer {
            if hasScopedAccess {
                securityScopedResourceAccessor.stopAccessing(sourceURL)
            }
        }

        do {
            let values = try sourceURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isDirectory != true,
                  values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                throw SongLibraryStageError.unsupportedSource
            }

            let partialURL = try paths.transactionPartialStageFileURL(operationID: operationID)
            try fileManager.copyItem(at: sourceURL, to: partialURL)
            if Task.isCancelled {
                throw CancellationError()
            }
            let handle = try FileHandle(forWritingTo: partialURL)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            let observed = try observedFile(at: partialURL)
            guard let fingerprint = observed.fingerprint else {
                throw SongLibraryStageError.unsupportedSource
            }
            let stagedURL = try paths.transactionStageFileURL(
                operationID: operationID,
                safeFileName: safeFileName
            )
            try fileManager.moveItem(at: partialURL, to: stagedURL)
            let stagedJournal = try SongLibraryImportJournal(
                operationID: operationID,
                kind: .unclassified,
                phase: .staged,
                safeFileName: safeFileName,
                stagedFingerprint: fingerprint
            )
            do {
                try writeJournal(stagedJournal)
            } catch {
                await discardFailedStage(operationID: operationID)
                return .blocked(
                    SongLibraryBlockedImport(
                        operationID: operationID,
                        message: "无法完成曲谱暂存记录，已停止本批导入。"
                    )
                )
            }
            return .staged(SongLibraryStagedImport(id: operationID, fileName: safeFileName))
        } catch is CancellationError {
            await discardFailedStage(operationID: operationID)
            return .itemFailure(itemFailure(fileName: safeFileName, message: "导入已取消。"))
        } catch SongLibraryStageError.unsupportedSource {
            await discardFailedStage(operationID: operationID)
            return .itemFailure(itemFailure(fileName: safeFileName, message: "所选项目不是可读取的普通文件。"))
        } catch {
            await discardFailedStage(operationID: operationID)
            return .itemFailure(itemFailure(fileName: safeFileName, message: "无法读取或暂存该曲谱。"))
        }
    }

    private func commitNewImport(
        journal: SongLibraryImportJournal
    ) async throws -> SongLibraryImportProcessResult {
        guard let stagedFingerprint = journal.stagedFingerprint else {
            throw SongLibraryTransactionServiceError.changedFile
        }
        let songID = makeUUID()
        let payload = SongLibraryNewEntryPayload(
            songID: songID,
            displayName: URL(fileURLWithPath: journal.safeFileName)
                .deletingPathExtension()
                .lastPathComponent,
            musicXMLFileName: journal.safeFileName,
            importedAt: now(),
            scoreFileVersionID: makeUUID()
        )
        let resolvedJournal = try SongLibraryImportJournal(
            operationID: journal.operationID,
            kind: .newImport,
            phase: .targetInstalled,
            safeFileName: journal.safeFileName,
            stagedFingerprint: stagedFingerprint,
            newEntry: payload
        )
        try writeJournal(resolvedJournal)

        do {
            let facts = try await recoveryFacts(for: resolvedJournal)
            try moveStageToTarget(journal: resolvedJournal, facts: facts)
        } catch {
            try? writeJournal(journal)
            _ = await cancel(operationID: journal.operationID)
            return .itemFailure(
                itemFailure(fileName: journal.safeFileName, message: "目标文件在导入时发生变化，请重试。")
            )
        }

        let updatedIndex: SongLibraryIndex
        do {
            updatedIndex = try await indexStore.appendUserEntry(payload.entry)
        } catch {
            do {
                try moveTargetBackToStage(journal: resolvedJournal)
                try writeJournal(journal)
                _ = await cancel(operationID: journal.operationID)
                return .itemFailure(
                    itemFailure(fileName: journal.safeFileName, message: "无法保存曲库索引，该项未导入。")
                )
            } catch {
                return .blocked(
                    SongLibraryBlockedImport(
                        operationID: journal.operationID,
                        message: "导入回滚未完成，请重新启动后恢复。"
                    )
                )
            }
        }

        let committedJournal = try SongLibraryImportJournal(
            operationID: resolvedJournal.operationID,
            kind: resolvedJournal.kind,
            phase: .indexCommitted,
            safeFileName: resolvedJournal.safeFileName,
            stagedFingerprint: stagedFingerprint,
            newEntry: payload
        )
        do {
            try writeJournal(committedJournal)
            let facts = try await recoveryFacts(for: committedJournal)
            try removeOperationDirectory(for: committedJournal, facts: facts)
        } catch {
            _ = await diagnostics.record(
                DiagnosticEvent(
                    severity: .warning,
                    code: .libraryImportCleanupFailed,
                    category: .library,
                    stage: "commitNewImport",
                    summary: "曲谱已导入但事务清理未完成",
                    reason: "事务文件已保留供下次启动恢复",
                    songID: songID,
                    persistence: .systemOnly
                )
            )
        }
        return .committed(index: updatedIndex, entry: payload.entry)
    }

    private func commitIndexedReplacement(
        journal: SongLibraryImportJournal,
        entry: SongLibraryEntry
    ) async -> SongLibraryImportProcessResult {
        await commitExistingEntry(
            journal: journal,
            entry: entry,
            kind: .indexedReplace,
            backsUpTarget: true
        )
    }

    private func commitMissingTargetRepair(
        journal: SongLibraryImportJournal,
        entry: SongLibraryEntry
    ) async -> SongLibraryImportProcessResult {
        await commitExistingEntry(
            journal: journal,
            entry: entry,
            kind: .missingTargetRepair,
            backsUpTarget: false
        )
    }

    private func commitExistingEntry(
        journal: SongLibraryImportJournal,
        entry: SongLibraryEntry,
        kind: SongLibraryImportOperationKind,
        backsUpTarget: Bool
    ) async -> SongLibraryImportProcessResult {
        guard let stagedFingerprint = journal.stagedFingerprint else {
            return blockedImport(journal, message: "暂存曲谱事实不完整，请重新导入。")
        }
        let expected = SongLibraryExpectedEntryIdentity(
            songID: entry.id,
            scoreFileVersionID: entry.scoreFileVersionID,
            musicXMLFileName: entry.musicXMLFileName
        )
        let payload = SongLibraryNewEntryPayload(
            songID: entry.id,
            displayName: entry.displayName,
            musicXMLFileName: journal.safeFileName,
            importedAt: now(),
            scoreFileVersionID: makeUUID()
        )
        let backupFingerprint: TransactionFileFingerprint?
        do {
            let target = try observedFile(
                at: paths.scoreFileURL(safeFileName: journal.safeFileName)
            )
            guard target.exists == backsUpTarget else {
                return await process(operationID: journal.operationID)
            }
            backupFingerprint = backsUpTarget ? target.fingerprint : nil
            if backsUpTarget, backupFingerprint == nil {
                return blockedImport(journal, message: "无法核对现有曲谱文件，请重试。")
            }
        } catch {
            return blockedImport(journal, message: "无法核对现有曲谱文件，请重试。")
        }

        let resolved: SongLibraryImportJournal
        do {
            resolved = try SongLibraryImportJournal(
                operationID: journal.operationID,
                kind: kind,
                phase: backsUpTarget ? .backupMoved : .targetInstalled,
                safeFileName: journal.safeFileName,
                stagedFingerprint: stagedFingerprint,
                backupFingerprint: backupFingerprint,
                expectedEntry: expected,
                newEntry: payload
            )
            try writeJournal(resolved)
        } catch {
            return blockedImport(journal, message: "无法记录曲谱替换事务，请修复存储后重试。")
        }
        do {
            if backsUpTarget {
                try moveTargetToBackup(journal: resolved)
            }
            let facts = try await recoveryFacts(for: resolved)
            try moveStageToTarget(journal: resolved, facts: facts)
            try writeJournal(try self.journal(resolved, phase: .targetInstalled))
        } catch {
            guard await rollbackResolvedImport(resolvedJournal: resolved, stagedJournal: journal) else {
                return blockedImport(journal, message: "曲谱替换回滚未完成，请重新启动后恢复。")
            }
            return .itemFailure(
                itemFailure(fileName: journal.safeFileName, message: "曲谱文件在确认期间发生变化，请重试。")
            )
        }

        do {
            let replacement = SongLibraryScoreReplacement(
                musicXMLFileName: payload.musicXMLFileName,
                importedAt: payload.importedAt,
                scoreFileVersionID: payload.scoreFileVersionID
            )
            switch try await indexStore.replaceUserScore(
                expectedSongID: expected.songID,
                expectedScoreFileVersionID: expected.scoreFileVersionID,
                expectedMusicXMLFileName: expected.musicXMLFileName,
                with: replacement
            ) {
            case let .applied(updatedIndex, updatedEntry):
                return await finishCommittedImport(
                    journal: resolved,
                    index: updatedIndex,
                    entry: updatedEntry
                )
            case .conflict:
                guard await rollbackResolvedImport(
                    resolvedJournal: resolved,
                    stagedJournal: journal
                ) else {
                    return blockedImport(journal, message: "曲谱替换与索引竞争且回滚未完成，请重新启动后恢复。")
                }
                return await process(operationID: journal.operationID)
            }
        } catch {
            guard await rollbackResolvedImport(resolvedJournal: resolved, stagedJournal: journal) else {
                return blockedImport(journal, message: "曲谱替换回滚未完成，请重新启动后恢复。")
            }
            return .itemFailure(
                itemFailure(fileName: journal.safeFileName, message: "无法保存曲谱替换，该项未修改。")
            )
        }
    }

    private func commitOrphanAdoption(
        journal: SongLibraryImportJournal
    ) async -> SongLibraryImportProcessResult {
        guard let stagedFingerprint = journal.stagedFingerprint else {
            return blockedImport(journal, message: "暂存曲谱事实不完整，请重新导入。")
        }
        let target: SongLibraryObservedTransactionFile
        do {
            target = try observedFile(at: paths.scoreFileURL(safeFileName: journal.safeFileName))
        } catch {
            return blockedImport(journal, message: "无法核对未索引曲谱文件，请重试。")
        }
        guard target.exists, let backupFingerprint = target.fingerprint else {
            return await process(operationID: journal.operationID)
        }
        let payload = SongLibraryNewEntryPayload(
            songID: makeUUID(),
            displayName: URL(fileURLWithPath: journal.safeFileName)
                .deletingPathExtension()
                .lastPathComponent,
            musicXMLFileName: journal.safeFileName,
            importedAt: now(),
            scoreFileVersionID: makeUUID()
        )
        let resolved: SongLibraryImportJournal
        do {
            resolved = try SongLibraryImportJournal(
                operationID: journal.operationID,
                kind: .orphanAdopt,
                phase: .backupMoved,
                safeFileName: journal.safeFileName,
                stagedFingerprint: stagedFingerprint,
                backupFingerprint: backupFingerprint,
                newEntry: payload
            )
            try writeJournal(resolved)
        } catch {
            return blockedImport(journal, message: "无法记录未索引曲谱事务，请修复存储后重试。")
        }
        do {
            try moveTargetToBackup(journal: resolved)
            let facts = try await recoveryFacts(for: resolved)
            try moveStageToTarget(journal: resolved, facts: facts)
            try writeJournal(try self.journal(resolved, phase: .targetInstalled))
        } catch {
            guard await rollbackResolvedImport(resolvedJournal: resolved, stagedJournal: journal) else {
                return blockedImport(journal, message: "未索引曲谱替换回滚未完成，请重新启动后恢复。")
            }
            return .itemFailure(
                itemFailure(fileName: journal.safeFileName, message: "未索引曲谱在确认期间发生变化，请重试。")
            )
        }

        do {
            let updatedIndex = try await indexStore.appendUserEntry(payload.entry)
            return await finishCommittedImport(
                journal: resolved,
                index: updatedIndex,
                entry: payload.entry
            )
        } catch {
            guard await rollbackResolvedImport(resolvedJournal: resolved, stagedJournal: journal) else {
                return blockedImport(journal, message: "未索引曲谱替换回滚未完成，请重新启动后恢复。")
            }
            return .itemFailure(
                itemFailure(fileName: journal.safeFileName, message: "无法保存曲库索引，该项未导入。")
            )
        }
    }

    private func journal(
        _ journal: SongLibraryImportJournal,
        phase: SongLibraryImportJournalPhase
    ) throws -> SongLibraryImportJournal {
        try SongLibraryImportJournal(
            operationID: journal.operationID,
            kind: journal.kind,
            phase: phase,
            safeFileName: journal.safeFileName,
            stagedFingerprint: journal.stagedFingerprint,
            backupFingerprint: journal.backupFingerprint,
            expectedEntry: journal.expectedEntry,
            newEntry: journal.newEntry
        )
    }

    private func moveTargetToBackup(journal: SongLibraryImportJournal) throws {
        guard let backupFingerprint = journal.backupFingerprint,
              let stagedFingerprint = journal.stagedFingerprint
        else { throw SongLibraryTransactionServiceError.changedFile }
        let targetURL = try paths.scoreFileURL(safeFileName: journal.safeFileName)
        let backupURL = try paths.transactionBackupFileURL(
            operationID: journal.operationID,
            safeFileName: journal.safeFileName
        )
        let stageURL = try paths.transactionStageFileURL(
            operationID: journal.operationID,
            safeFileName: journal.safeFileName
        )
        guard try observedFile(at: targetURL).fingerprint == backupFingerprint,
              try observedFile(at: backupURL).exists == false,
              try observedFile(at: stageURL).fingerprint == stagedFingerprint
        else { throw SongLibraryTransactionServiceError.changedFile }
        try fileManager.createDirectory(
            at: backupURL.deletingLastPathComponent(),
            withIntermediateDirectories: false
        )
        try fileManager.moveItem(at: targetURL, to: backupURL)
        guard try observedFile(at: backupURL).fingerprint == backupFingerprint else {
            throw SongLibraryTransactionServiceError.changedFile
        }
    }

    private func rollbackResolvedImport(
        resolvedJournal: SongLibraryImportJournal?,
        stagedJournal: SongLibraryImportJournal
    ) async -> Bool {
        guard let resolvedJournal else { return true }
        do {
            let targetURL = try paths.scoreFileURL(safeFileName: resolvedJournal.safeFileName)
            let stageURL = try paths.transactionStageFileURL(
                operationID: resolvedJournal.operationID,
                safeFileName: resolvedJournal.safeFileName
            )
            let backupURL = try paths.transactionBackupFileURL(
                operationID: resolvedJournal.operationID,
                safeFileName: resolvedJournal.safeFileName
            )
            let target = try observedFile(at: targetURL)
            if target.exists {
                if target.fingerprint == resolvedJournal.stagedFingerprint {
                    guard try observedFile(at: stageURL).exists == false else { return false }
                    try fileManager.moveItem(at: targetURL, to: stageURL)
                } else if target.fingerprint != resolvedJournal.backupFingerprint {
                    return false
                }
            }
            let backup = try observedFile(at: backupURL)
            if backup.exists {
                guard backup.fingerprint == resolvedJournal.backupFingerprint,
                      try observedFile(at: targetURL).exists == false
                else { return false }
                try fileManager.moveItem(at: backupURL, to: targetURL)
            }
            try writeJournal(stagedJournal)
            return true
        } catch {
            return false
        }
    }

    private func finishCommittedImport(
        journal: SongLibraryImportJournal,
        index: SongLibraryIndex,
        entry: SongLibraryEntry
    ) async -> SongLibraryImportProcessResult {
        do {
            let committed = try self.journal(journal, phase: .indexCommitted)
            try writeJournal(committed)
            try removeOperationDirectory(
                for: committed,
                facts: try await recoveryFacts(for: committed)
            )
        } catch {
            _ = await diagnostics.record(
                DiagnosticEvent(
                    severity: .warning,
                    code: .libraryImportCleanupFailed,
                    category: .library,
                    stage: "finishImport",
                    summary: "曲谱已提交但事务清理未完成",
                    reason: "事务文件已保留供下次启动恢复",
                    songID: entry.id,
                    persistence: .systemOnly
                )
            )
        }
        return .committed(index: index, entry: entry)
    }

    private func blockedImport(
        _ journal: SongLibraryImportJournal,
        message: String
    ) -> SongLibraryImportProcessResult {
        .blocked(
            SongLibraryBlockedImport(
                operationID: journal.operationID,
                message: message
            )
        )
    }

    private func moveTargetBackToStage(journal: SongLibraryImportJournal) throws {
        let targetURL = try paths.scoreFileURL(safeFileName: journal.safeFileName)
        let target = try observedFile(at: targetURL)
        guard target.fingerprint == journal.stagedFingerprint else {
            throw SongLibraryTransactionServiceError.changedFile
        }
        let stageURL = try paths.transactionStageFileURL(
            operationID: journal.operationID,
            safeFileName: journal.safeFileName
        )
        guard fileManager.fileExists(atPath: stageURL.path(percentEncoded: false)) == false else {
            throw SongLibraryTransactionServiceError.changedFile
        }
        try fileManager.moveItem(at: targetURL, to: stageURL)
    }

    private func targetVolumeFacts(
        safeFileName: String
    ) throws -> SongLibraryImportTargetVolumeFacts {
        let targetURL = try paths.scoreFileURL(safeFileName: safeFileName)
        guard fileManager.fileExists(atPath: targetURL.path(percentEncoded: false)) else {
            return SongLibraryImportTargetVolumeFacts(
                candidateExists: false,
                candidateResourceIdentifier: nil,
                fileNamesWithCandidateResourceIdentifier: []
            )
        }
        guard try isPlainFile(targetURL) else {
            throw SongLibraryTransactionServiceError.unsafePath
        }
        let candidateIdentifier = try targetURL.resourceValues(
            forKeys: [.fileResourceIdentifierKey]
        ).fileResourceIdentifier
        var matchingNames: [String] = []
        if let candidateIdentifier {
            let directoryItems = try fileManager.contentsOfDirectory(
                at: paths.scoresDirectoryURL(),
                includingPropertiesForKeys: [
                    .fileResourceIdentifierKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ],
                options: []
            )
            for item in directoryItems {
                let values = try item.resourceValues(
                    forKeys: [
                        .fileResourceIdentifierKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                    ]
                )
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      let itemIdentifier = values.fileResourceIdentifier,
                      resourceIdentifiersAreEqual(candidateIdentifier, itemIdentifier)
                else { continue }
                matchingNames.append(item.lastPathComponent)
            }
        }
        return SongLibraryImportTargetVolumeFacts(
            candidateExists: true,
            candidateResourceIdentifier: candidateIdentifier.map { String(describing: $0) },
            fileNamesWithCandidateResourceIdentifier: matchingNames
        )
    }

    private func resourceIdentifiersAreEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        guard let lhsObject = lhs as? NSObject else { return false }
        return lhsObject.isEqual(rhs)
    }

    private func isValidSourceFileName(_ fileName: String) -> Bool {
        guard fileName.isEmpty == false,
              fileName != ".",
              fileName != "..",
              fileName.contains("/") == false,
              fileName.contains("\\") == false,
              SongLibraryFileNameIdentity.isExact(
                URL(fileURLWithPath: fileName).lastPathComponent,
                fileName
              )
        else { return false }
        return Self.supportedScoreExtensions.contains(
            URL(fileURLWithPath: fileName).pathExtension.lowercased()
        )
    }

    private func itemFailure(fileName: String, message: String) -> SongLibraryImportItemFailure {
        SongLibraryImportItemFailure(
            fileName: fileName.isEmpty ? "未命名项目" : fileName,
            message: message
        )
    }

    private func discardFailedStage(operationID: UUID) async {
        do {
            let operationDirectory = try paths.transactionOperationDirectoryURL(operationID: operationID)
            guard fileManager.fileExists(atPath: operationDirectory.path(percentEncoded: false)) else { return }
            let journalURL = try paths.transactionJournalFileURL(operationID: operationID)
            if fileManager.fileExists(atPath: journalURL.path(percentEncoded: false)) {
                guard await cancel(operationID: operationID) else {
                    throw SongLibraryTransactionServiceError.changedFile
                }
            } else if try isSafeJournalLessScratch(operationDirectory) {
                try fileManager.removeItem(at: operationDirectory)
            } else {
                throw SongLibraryTransactionServiceError.unsafePath
            }
        } catch {
            _ = await diagnostics.record(
                DiagnosticEvent(
                    severity: .warning,
                    code: .libraryImportCleanupFailed,
                    category: .library,
                    stage: "stageImport",
                    summary: "无法清理未完成的曲谱暂存",
                    reason: "事务目录已保留供下次启动恢复",
                    persistence: .systemOnly
                )
            )
        }
    }

    private func writeJournal(_ journal: SongLibraryImportJournal) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(journal).write(
            to: paths.transactionJournalFileURL(operationID: journal.operationID),
            options: .atomic
        )
    }

    private func loadJournal(operationID: UUID) throws -> SongLibraryImportJournal {
        let journal = try decodeJournal(
            at: paths.transactionJournalFileURL(operationID: operationID)
        )
        guard journal.operationID == operationID,
              try isSafeRecordedOperationDirectory(
                paths.transactionOperationDirectoryURL(operationID: operationID),
                journal: journal
              )
        else {
            throw SongLibraryTransactionServiceError.unsafePath
        }
        return journal
    }

    func recoverPendingTransactions() async -> SongLibraryTransactionRecoveryResult {
        do {
            try ensureRecoveryDirectoriesAreSafe()
            let root = try paths.transactionsDirectoryURL()
            let operationDirectories = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
            for operationDirectory in operationDirectories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let operationID = UUID(uuidString: operationDirectory.lastPathComponent),
                      operationDirectory.lastPathComponent == operationID.uuidString.lowercased(),
                      try isPlainDirectory(operationDirectory)
                else {
                    return await blocked(operationID: nil, reason: "发现未知事务目录")
                }

                let result: SongLibraryTransactionRecoveryResult
                do {
                    result = try await recoverOperationDirectory(
                        operationDirectory,
                        operationID: operationID
                    )
                } catch {
                    return await blocked(operationID: operationID, reason: "事务内容无法安全读取")
                }
                if case .blocked = result {
                    return result
                }
            }
            return .recovered
        } catch {
            return await blocked(operationID: nil, reason: "事务恢复失败")
        }
    }

    private func ensureRecoveryDirectoriesAreSafe() throws {
        try ensurePlainDirectory(at: paths.rootDirectoryURL())
        try ensurePlainDirectory(at: paths.scoresDirectoryURL())
        try ensurePlainDirectory(at: paths.transactionsDirectoryURL())
    }

    private func ensurePlainDirectory(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            guard try isPlainDirectory(url) else {
                throw SongLibraryTransactionServiceError.unsafePath
            }
            return
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        guard try isPlainDirectory(url) else {
            throw SongLibraryTransactionServiceError.unsafePath
        }
    }

    private func recoverOperationDirectory(
        _ operationDirectory: URL,
        operationID: UUID
    ) async throws -> SongLibraryTransactionRecoveryResult {
        let journalURL = try paths.transactionJournalFileURL(operationID: operationID)
        guard fileManager.fileExists(atPath: journalURL.path(percentEncoded: false)) else {
            guard try isSafeJournalLessScratch(operationDirectory) else {
                return await blocked(operationID: operationID, reason: "无法确认未记录事务的所有权")
            }
            try fileManager.removeItem(at: operationDirectory)
            return .recovered
        }

        let journal = try decodeJournal(at: journalURL)
        guard journal.operationID == operationID else {
            return await blocked(operationID: operationID, reason: "事务标识不一致")
        }
        guard try isSafeRecordedOperationDirectory(operationDirectory, journal: journal) else {
            return await blocked(operationID: operationID, reason: "事务目录包含未知内容")
        }
        return try await recover(journal: journal)
    }

    private func recover(journal: SongLibraryImportJournal) async throws -> SongLibraryTransactionRecoveryResult {
        for _ in 0..<8 {
            let facts = try await recoveryFacts(for: journal)
            switch SongLibraryTransactionRecoveryPlanner.action(journal: journal, facts: facts) {
            case .cleanup:
                try removeOperationDirectory(for: journal, facts: facts)
                return .recovered
            case .rollForwardTarget:
                try moveStageToTarget(journal: journal, facts: facts)
            case .commitIndex:
                guard try await commitIndex(journal: journal) else {
                    return await blocked(operationID: journal.operationID, reason: "索引事实已变化")
                }
            case .restoreBackup:
                try restoreBackup(journal: journal, facts: facts)
            case .removeUncommittedTarget:
                try removeUncommittedTarget(journal: journal, facts: facts)
            case .block:
                return await blocked(operationID: journal.operationID, reason: "事务文件或索引事实不一致")
            }
        }
        return await blocked(operationID: journal.operationID, reason: "事务恢复未能收敛")
    }

    private func recoveryFacts(for journal: SongLibraryImportJournal) async throws -> SongLibraryTransactionRecoveryFacts {
        let stageURL = try paths.transactionStageFileURL(
            operationID: journal.operationID,
            safeFileName: journal.safeFileName
        )
        let backupURL = try paths.transactionBackupFileURL(
            operationID: journal.operationID,
            safeFileName: journal.safeFileName
        )
        if journal.kind == .unclassified {
            return SongLibraryTransactionRecoveryFacts(
                stage: try observedFile(at: stageURL),
                backup: try observedFile(at: backupURL),
                target: .missing,
                indexState: .neither
            )
        }
        let targetURL = try paths.scoreFileURL(safeFileName: journal.safeFileName)
        return SongLibraryTransactionRecoveryFacts(
            stage: try observedFile(at: stageURL),
            backup: try observedFile(at: backupURL),
            target: try observedFile(at: targetURL),
            indexState: try await indexState(for: journal)
        )
    }

    private func indexState(for journal: SongLibraryImportJournal) async throws -> SongLibraryRecoveryIndexState {
        let index = try await indexStore.load()
        guard let payload = journal.newEntry else {
            return .neither
        }
        let matchingEntries = index.entries.filter { $0.id == payload.songID && $0.isBundled != true }
        guard matchingEntries.count <= 1 else { return .conflicting }
        guard let actual = matchingEntries.first else { return .neither }
        if SongLibraryFileNameIdentity.isExact(
            actual.musicXMLFileName,
            payload.musicXMLFileName
        ),
           actual.scoreFileVersionID == payload.scoreFileVersionID
        {
            return .newEntryPresent
        }
        if let expected = journal.expectedEntry,
           actual.id == expected.songID,
           SongLibraryFileNameIdentity.isExact(
            actual.musicXMLFileName,
            expected.musicXMLFileName
           ),
           actual.scoreFileVersionID == expected.scoreFileVersionID
        {
            return .expectedEntryPresent
        }
        return .conflicting
    }

    private func commitIndex(journal: SongLibraryImportJournal) async throws -> Bool {
        guard let payload = journal.newEntry else { return false }
        switch journal.kind {
        case .newImport, .orphanAdopt:
            _ = try await indexStore.appendUserEntry(payload.entry)
            return true
        case .indexedReplace, .missingTargetRepair:
            guard let expected = journal.expectedEntry else { return false }
            let result = try await indexStore.replaceUserScore(
                expectedSongID: expected.songID,
                expectedScoreFileVersionID: expected.scoreFileVersionID,
                expectedMusicXMLFileName: expected.musicXMLFileName,
                with: SongLibraryScoreReplacement(
                    musicXMLFileName: payload.musicXMLFileName,
                    importedAt: payload.importedAt,
                    scoreFileVersionID: payload.scoreFileVersionID
                )
            )
            if case .applied = result { return true }
            return false
        case .unclassified:
            return false
        }
    }

    private func moveStageToTarget(
        journal: SongLibraryImportJournal,
        facts: SongLibraryTransactionRecoveryFacts
    ) throws {
        let currentStage = try observedFile(
            at: paths.transactionStageFileURL(
                operationID: journal.operationID,
                safeFileName: journal.safeFileName
            )
        )
        let currentTarget = try observedFile(
            at: paths.scoreFileURL(safeFileName: journal.safeFileName)
        )
        guard facts.target.exists == false,
              currentTarget.exists == false,
              facts.stage.fingerprint == journal.stagedFingerprint,
              currentStage.fingerprint == journal.stagedFingerprint
        else { throw SongLibraryTransactionServiceError.changedFile }
        try fileManager.moveItem(
            at: paths.transactionStageFileURL(operationID: journal.operationID, safeFileName: journal.safeFileName),
            to: paths.scoreFileURL(safeFileName: journal.safeFileName)
        )
    }

    private func restoreBackup(
        journal: SongLibraryImportJournal,
        facts: SongLibraryTransactionRecoveryFacts
    ) throws {
        let currentBackup = try observedFile(
            at: paths.transactionBackupFileURL(
                operationID: journal.operationID,
                safeFileName: journal.safeFileName
            )
        )
        let currentTarget = try observedFile(
            at: paths.scoreFileURL(safeFileName: journal.safeFileName)
        )
        guard facts.target.exists == false,
              currentTarget.exists == false,
              facts.backup.fingerprint == journal.backupFingerprint,
              currentBackup.fingerprint == journal.backupFingerprint
        else { throw SongLibraryTransactionServiceError.changedFile }
        try fileManager.moveItem(
            at: paths.transactionBackupFileURL(operationID: journal.operationID, safeFileName: journal.safeFileName),
            to: paths.scoreFileURL(safeFileName: journal.safeFileName)
        )
    }

    private func removeUncommittedTarget(
        journal: SongLibraryImportJournal,
        facts: SongLibraryTransactionRecoveryFacts
    ) throws {
        let currentTarget = try observedFile(
            at: paths.scoreFileURL(safeFileName: journal.safeFileName)
        )
        guard facts.target.fingerprint == journal.stagedFingerprint,
              currentTarget.fingerprint == journal.stagedFingerprint
        else {
            throw SongLibraryTransactionServiceError.changedFile
        }
        try fileManager.removeItem(at: paths.scoreFileURL(safeFileName: journal.safeFileName))
    }

    private func removeOperationDirectory(
        for journal: SongLibraryImportJournal,
        facts: SongLibraryTransactionRecoveryFacts
    ) throws {
        let currentStage = try observedFile(
            at: paths.transactionStageFileURL(
                operationID: journal.operationID,
                safeFileName: journal.safeFileName
            )
        )
        let currentBackup = try observedFile(
            at: paths.transactionBackupFileURL(
                operationID: journal.operationID,
                safeFileName: journal.safeFileName
            )
        )
        guard facts.stage == currentStage,
              facts.backup == currentBackup,
              currentStage.exists == false
                || journal.phase == .preparing
                || currentStage.fingerprint == journal.stagedFingerprint,
              currentBackup.exists == false || currentBackup.fingerprint == journal.backupFingerprint,
              try containsNoSymbolicLinks(
                paths.transactionOperationDirectoryURL(operationID: journal.operationID)
              )
        else { throw SongLibraryTransactionServiceError.changedFile }
        try fileManager.removeItem(
            at: paths.transactionOperationDirectoryURL(operationID: journal.operationID)
        )
    }

    private func decodeJournal(at url: URL) throws -> SongLibraryImportJournal {
        guard try isPlainFile(url) else { throw SongLibraryTransactionServiceError.unsafePath }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return try decoder.decode(SongLibraryImportJournal.self, from: Data(contentsOf: url))
    }

    private func observedFile(at url: URL) throws -> SongLibraryObservedTransactionFile {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return .missing }
        guard try isPlainFile(url) else { throw SongLibraryTransactionServiceError.unsafePath }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let data = try handle.read(upToCount: 64 * 1024), data.isEmpty == false {
            byteCount += Int64(data.count)
            hasher.update(data: data)
        }
        let digits = Array("0123456789abcdef")
        let digest = hasher.finalize().flatMap { byte in
            [digits[Int(byte >> 4)], digits[Int(byte & 0x0f)]]
        }
        let digestText = String(digest)
        let fingerprint = try TransactionFileFingerprint(byteCount: byteCount, sha256: digestText)
        let values = try url.resourceValues(forKeys: [.fileResourceIdentifierKey])
        return SongLibraryObservedTransactionFile(
            exists: true,
            fingerprint: fingerprint,
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) }
        )
    }

    private func isSafeJournalLessScratch(_ directory: URL) throws -> Bool {
        guard try containsNoSymbolicLinks(directory) else { return false }
        let children = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard children.count <= 1 else { return false }
        guard let stageDirectory = children.first else { return true }
        guard stageDirectory.lastPathComponent == "stage" else { return false }
        return try isPlainDirectory(stageDirectory)
    }

    private func isSafeRecordedOperationDirectory(
        _ directory: URL,
        journal: SongLibraryImportJournal
    ) throws -> Bool {
        guard try containsNoSymbolicLinks(directory) else { return false }
        let children = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let allowedNames = Set(["journal.json", "stage", "backup"])
        guard children.allSatisfy({ allowedNames.contains($0.lastPathComponent) }) else {
            return false
        }
        for child in children where child.lastPathComponent == "stage" || child.lastPathComponent == "backup" {
            guard try isPlainDirectory(child) else { return false }
            let files = try fileManager.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)
            let allowedFileNames = journal.phase == .preparing
                ? Set([journal.safeFileName, ".partial"])
                : Set([journal.safeFileName])
            guard files.count <= 1,
                  files.allSatisfy({ allowedFileNames.contains($0.lastPathComponent) })
            else { return false }
        }
        return true
    }

    private func containsNoSymbolicLinks(_ directory: URL) throws -> Bool {
        guard try isPlainDirectory(directory) else { return false }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else { return false }
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                return false
            }
        }
        return true
    }

    private func isPlainDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func isPlainFile(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func blocked(operationID: UUID?, reason: String) async -> SongLibraryTransactionRecoveryResult {
        _ = await diagnostics.record(
            DiagnosticEvent(
                severity: .error,
                code: .libraryImportRecoveryBlocked,
                category: .library,
                stage: "importRecovery",
                summary: "曲谱导入事务恢复被阻止",
                reason: reason,
                songID: nil,
                persistence: .systemOnly
            )
        )
        return .blocked(
            SongLibraryBlockedImport(
                operationID: operationID,
                message: "曲谱导入恢复需要处理，请修复文件后重试。"
            )
        )
    }
}

private enum SongLibraryTransactionServiceError: Error {
    case unsafePath
    case changedFile
}

private enum SongLibraryStageError: Error {
    case unsupportedSource
}

private enum SongLibraryStageOneResult {
    case staged(SongLibraryStagedImport)
    case itemFailure(SongLibraryImportItemFailure)
    case blocked(SongLibraryBlockedImport)
}
