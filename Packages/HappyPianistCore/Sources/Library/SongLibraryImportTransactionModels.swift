import Foundation

enum SongLibraryImportOperationKind: String, Codable, Equatable {
    case unclassified
    case newImport
    case indexedReplace
    case missingTargetRepair
    case orphanAdopt
}

public enum SongLibraryImportConflictKind: Equatable, Sendable {
    case none
    case indexedTarget(entry: SongLibraryEntry)
    case indexedMissingTarget(entry: SongLibraryEntry)
    case filesystemOrphan
    case ambiguousIndexedTargets(entries: [SongLibraryEntry])
}

enum SongLibraryImportJournalPhase: String, Codable, Equatable {
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
    case inconsistentResolvedIdentity
}

struct TransactionFileFingerprint: Codable, Equatable {
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

struct SongLibraryExpectedEntryIdentity: Codable, Equatable {
    let songID: UUID
    let scoreFileVersionID: UUID
    let musicXMLFileName: String
}

struct SongLibraryNewEntryPayload: Codable, Equatable {
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

struct SongLibraryImportJournal: Codable, Equatable {
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
            let expectsBackup = kind == .indexedReplace || kind == .orphanAdopt
            guard kind != .unclassified,
                  stagedFingerprint != nil,
                  newEntry != nil,
                  expectsExistingEntry == (expectedEntry != nil),
                  expectsBackup == (backupFingerprint != nil)
            else {
                throw SongLibraryImportTransactionModelError.unresolvedJournalPhase
            }
            guard let newEntry,
                  SongLibraryFileNameIdentity.isExact(
                      newEntry.musicXMLFileName,
                      safeFileName
                  ),
                  expectedEntry.map({ $0.songID == newEntry.songID }) ?? true
            else {
                throw SongLibraryImportTransactionModelError.inconsistentResolvedIdentity
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

public struct SongLibraryPendingImport: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let fileName: String
    public let conflict: SongLibraryImportConflictKind

    public init(id: UUID, fileName: String, conflict: SongLibraryImportConflictKind) {
        self.id = id
        self.fileName = fileName
        self.conflict = conflict
    }
}

public struct SongLibraryStagedImport: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let fileName: String

    public init(id: UUID, fileName: String) {
        self.id = id
        self.fileName = fileName
    }
}

public struct SongLibraryImportItemFailure: Equatable, Sendable {
    public let fileName: String
    public let message: String

    public init(fileName: String, message: String) {
        self.fileName = fileName
        self.message = message
    }
}

public enum SongLibraryImportBatchItem: Equatable, Sendable {
    case staged(SongLibraryStagedImport)
    case failure(SongLibraryImportItemFailure)
}

public struct SongLibraryImportBatchStageResult: Equatable, Sendable {
    public let items: [SongLibraryImportBatchItem]
    public let blocked: SongLibraryBlockedImport?

    public init(items: [SongLibraryImportBatchItem], blocked: SongLibraryBlockedImport?) {
        self.items = items
        self.blocked = blocked
    }
}

public enum SongLibraryImportProcessResult: Equatable, Sendable {
    case committed(index: SongLibraryIndex, entry: SongLibraryEntry)
    case requiresConfirmation(SongLibraryPendingImport)
    case itemFailure(SongLibraryImportItemFailure)
    case blocked(SongLibraryBlockedImport)
}

public enum SongLibraryImportState: Equatable, Sendable {
    case idle
    case staging(count: Int)
    case processing(operationID: UUID, index: Int, count: Int)
    case awaitingConfirmation(SongLibraryPendingImport, index: Int, count: Int)
    case itemFailure(SongLibraryImportItemFailure, index: Int, count: Int)

    public var isActive: Bool {
        self != .idle
    }
}

public struct SongLibraryBlockedImport: Equatable, Sendable {
    public let operationID: UUID?
    public let message: String

    public init(operationID: UUID?, message: String) {
        self.operationID = operationID
        self.message = message
    }
}

public enum SongLibraryTransactionRecoveryResult: Equatable, Sendable {
    case recovered
    case blocked(SongLibraryBlockedImport)
}

public struct SongLibraryScoreReplacement: Equatable, Sendable {
    public let musicXMLFileName: String
    public let importedAt: Date
    public let scoreFileVersionID: UUID

    public init(musicXMLFileName: String, importedAt: Date, scoreFileVersionID: UUID) {
        self.musicXMLFileName = musicXMLFileName
        self.importedAt = importedAt
        self.scoreFileVersionID = scoreFileVersionID
    }
}

public enum SongLibraryScoreReplacementResult: Equatable, Sendable {
    case applied(index: SongLibraryIndex, entry: SongLibraryEntry)
    case conflict(index: SongLibraryIndex, matchingEntries: [SongLibraryEntry])

    public var index: SongLibraryIndex {
        switch self {
        case let .applied(index, _), let .conflict(index, _):
            index
        }
    }
}
