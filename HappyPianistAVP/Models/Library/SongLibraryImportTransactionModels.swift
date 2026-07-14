import Foundation

enum SongLibraryImportOperationKind: String, Codable, Equatable, Sendable {
    case unclassified
    case newImport
    case indexedReplace
    case missingTargetRepair
    case orphanAdopt
}

enum SongLibraryImportConflictKind: Equatable, Sendable {
    case none
    case indexedTarget(entry: SongLibraryEntry)
    case indexedMissingTarget(entry: SongLibraryEntry)
    case filesystemOrphan
    case ambiguousIndexedTargets(entries: [SongLibraryEntry])
}

enum SongLibraryImportJournalPhase: String, Codable, Equatable, Sendable {
    case preparing
    case staged
    case backupMoved
    case targetInstalled
    case indexCommitted
}

enum SongLibraryImportTransactionModelError: Error, Equatable {
    case invalidFingerprint
    case invalidSafeFileName
    case unresolvedJournalPhase
}

struct TransactionFileFingerprint: Codable, Equatable, Sendable {
    let byteCount: Int64
    let sha256: String

    init(byteCount: Int64, sha256: String) throws {
        guard byteCount >= 0,
              sha256.count == 64,
              sha256.allSatisfy({ "0123456789abcdef".contains($0) })
        else {
            throw SongLibraryImportTransactionModelError.invalidFingerprint
        }
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            byteCount: values.decode(Int64.self, forKey: .byteCount),
            sha256: values.decode(String.self, forKey: .sha256)
        )
    }
}

struct SongLibraryExpectedEntryIdentity: Codable, Equatable, Sendable {
    let songID: UUID
    let scoreFileVersionID: UUID?
    let musicXMLFileName: String
}

struct SongLibraryNewEntryPayload: Codable, Equatable, Sendable {
    let songID: UUID
    let displayName: String
    let musicXMLFileName: String
    let importedAt: Date
    let scoreFileVersionID: UUID

    var entry: SongLibraryEntry {
        SongLibraryEntry(
            id: songID,
            displayName: displayName,
            musicXMLFileName: musicXMLFileName,
            scoreFileVersionID: scoreFileVersionID,
            importedAt: importedAt,
            audioFileName: nil
        )
    }
}

struct SongLibraryImportJournal: Codable, Equatable, Sendable {
    let operationID: UUID
    let kind: SongLibraryImportOperationKind
    let phase: SongLibraryImportJournalPhase
    let safeFileName: String
    let stagedFingerprint: TransactionFileFingerprint?
    let backupFingerprint: TransactionFileFingerprint?
    let expectedEntry: SongLibraryExpectedEntryIdentity?
    let newEntry: SongLibraryNewEntryPayload?

    init(
        operationID: UUID,
        kind: SongLibraryImportOperationKind,
        phase: SongLibraryImportJournalPhase,
        safeFileName: String,
        stagedFingerprint: TransactionFileFingerprint? = nil,
        backupFingerprint: TransactionFileFingerprint? = nil,
        expectedEntry: SongLibraryExpectedEntryIdentity? = nil,
        newEntry: SongLibraryNewEntryPayload? = nil
    ) throws {
        guard safeFileName.isEmpty == false,
              safeFileName != ".",
              safeFileName != "..",
              safeFileName.contains("/") == false,
              safeFileName.contains("\\") == false,
              URL(fileURLWithPath: safeFileName).lastPathComponent == safeFileName
        else {
            throw SongLibraryImportTransactionModelError.invalidSafeFileName
        }
        if phase == .preparing || phase == .staged {
            guard kind == .unclassified,
                  backupFingerprint == nil,
                  expectedEntry == nil,
                  newEntry == nil
            else {
                throw SongLibraryImportTransactionModelError.unresolvedJournalPhase
            }
            if phase == .staged, stagedFingerprint == nil {
                throw SongLibraryImportTransactionModelError.unresolvedJournalPhase
            }
        } else {
            let expectsExistingEntry = kind == .indexedReplace || kind == .missingTargetRepair
            let expectsBackup = kind == .indexedReplace
            guard kind != .unclassified,
                  stagedFingerprint != nil,
                  newEntry != nil,
                  expectsExistingEntry == (expectedEntry != nil),
                  expectsBackup == (backupFingerprint != nil)
            else {
                throw SongLibraryImportTransactionModelError.unresolvedJournalPhase
            }
        }
        self.operationID = operationID
        self.kind = kind
        self.phase = phase
        self.safeFileName = safeFileName
        self.stagedFingerprint = stagedFingerprint
        self.backupFingerprint = backupFingerprint
        self.expectedEntry = expectedEntry
        self.newEntry = newEntry
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            operationID: values.decode(UUID.self, forKey: .operationID),
            kind: values.decode(SongLibraryImportOperationKind.self, forKey: .kind),
            phase: values.decode(SongLibraryImportJournalPhase.self, forKey: .phase),
            safeFileName: values.decode(String.self, forKey: .safeFileName),
            stagedFingerprint: values.decodeIfPresent(TransactionFileFingerprint.self, forKey: .stagedFingerprint),
            backupFingerprint: values.decodeIfPresent(TransactionFileFingerprint.self, forKey: .backupFingerprint),
            expectedEntry: values.decodeIfPresent(SongLibraryExpectedEntryIdentity.self, forKey: .expectedEntry),
            newEntry: values.decodeIfPresent(SongLibraryNewEntryPayload.self, forKey: .newEntry)
        )
    }
}

struct SongLibraryPendingImport: Equatable, Identifiable, Sendable {
    let id: UUID
    let fileName: String
    let conflict: SongLibraryImportConflictKind
}

struct SongLibraryStagedImport: Equatable, Identifiable, Sendable {
    let id: UUID
    let fileName: String
}

struct SongLibraryImportItemFailure: Equatable, Sendable {
    let fileName: String
    let message: String
}

enum SongLibraryImportBatchItem: Equatable, Sendable {
    case staged(SongLibraryStagedImport)
    case failure(SongLibraryImportItemFailure)
}

struct SongLibraryImportBatchStageResult: Equatable, Sendable {
    let items: [SongLibraryImportBatchItem]
    let blocked: SongLibraryBlockedImport?
}

enum SongLibraryImportProcessResult: Equatable, Sendable {
    case committed(index: SongLibraryIndex, entry: SongLibraryEntry)
    case requiresConfirmation(SongLibraryPendingImport)
    case itemFailure(SongLibraryImportItemFailure)
    case blocked(SongLibraryBlockedImport)
}

enum SongLibraryImportState: Equatable, Sendable {
    case idle
    case staging(index: Int, count: Int)
    case processing(operationID: UUID, index: Int, count: Int)
    case awaitingConfirmation(SongLibraryPendingImport, index: Int, count: Int)
    case itemFailure(SongLibraryImportItemFailure, index: Int, count: Int)

    var isActive: Bool { self != .idle }
}

struct SongLibraryBlockedImport: Equatable, Sendable {
    let operationID: UUID?
    let message: String
}

enum SongLibraryTransactionRecoveryResult: Equatable, Sendable {
    case recovered
    case blocked(SongLibraryBlockedImport)
}

struct SongLibraryScoreReplacement: Equatable, Sendable {
    let musicXMLFileName: String
    let importedAt: Date
    let scoreFileVersionID: UUID
}

enum SongLibraryScoreReplacementResult: Equatable, Sendable {
    case applied(index: SongLibraryIndex, entry: SongLibraryEntry)
    case conflict(index: SongLibraryIndex, matchingEntries: [SongLibraryEntry])

    var index: SongLibraryIndex {
        switch self {
        case let .applied(index, _), let .conflict(index, _):
            index
        }
    }
}
