import Foundation

struct SongLibraryImportTargetVolumeFacts: Equatable {
    let candidateExists: Bool
    let candidateResourceIdentifier: String?
    let fileNamesWithCandidateResourceIdentifier: [String]
}

enum SongLibraryImportConflictClassifier {
    static func classify(
        userEntries: [SongLibraryEntry],
        candidateFileName: String,
        targetFacts: SongLibraryImportTargetVolumeFacts
    ) -> SongLibraryImportConflictKind {
        let provenSameResourceNames = targetFacts.candidateResourceIdentifier == nil
            ? []
            : targetFacts.fileNamesWithCandidateResourceIdentifier
        let matchingEntries = userEntries.filter { entry in
            entry.isBundled != true
                && (SongLibraryFileNameIdentity.isExact(
                    entry.musicXMLFileName,
                    candidateFileName
                ) || provenSameResourceNames.contains(where: {
                    SongLibraryFileNameIdentity.isExact($0, entry.musicXMLFileName)
                }))
        }

        if matchingEntries.count > 1 {
            return .ambiguousIndexedTargets(entries: matchingEntries)
        }
        if let entry = matchingEntries.first {
            return targetFacts.candidateExists
                ? .indexedTarget(entry: entry)
                : .indexedMissingTarget(entry: entry)
        }
        return targetFacts.candidateExists ? .filesystemOrphan : .none
    }
}

struct SongLibraryObservedTransactionFile: Equatable {
    let exists: Bool
    let fingerprint: TransactionFileFingerprint?
    let resourceIdentifier: String?

    static let missing = SongLibraryObservedTransactionFile(
        exists: false,
        fingerprint: nil,
        resourceIdentifier: nil
    )
}

enum SongLibraryRecoveryIndexState: Equatable {
    case expectedEntryPresent
    case newEntryPresent
    case neither
    case conflicting
}

struct SongLibraryTransactionRecoveryFacts: Equatable {
    let stage: SongLibraryObservedTransactionFile
    let backup: SongLibraryObservedTransactionFile
    let target: SongLibraryObservedTransactionFile
    let indexState: SongLibraryRecoveryIndexState
}

enum SongLibraryTransactionRecoveryAction: Equatable {
    case cleanup
    case rollForwardTarget
    case commitIndex
    case restoreBackup
    case removeUncommittedTarget
    case block
}

enum SongLibraryTransactionRecoveryPlanner {
    static func action(
        journal: SongLibraryImportJournal,
        facts: SongLibraryTransactionRecoveryFacts
    ) -> SongLibraryTransactionRecoveryAction {
        guard hasNoAliasedPaths(facts) else { return .block }

        if journal.kind == .unclassified {
            guard facts.backup.exists == false,
                  journal.stagedFingerprint == nil
                  || matchesIfPresent(facts.stage, expected: journal.stagedFingerprint)
            else { return .block }
            return .cleanup
        }

        guard let stagedFingerprint = journal.stagedFingerprint,
              journal.newEntry != nil,
              facts.indexState != .conflicting,
              matchesIfPresent(facts.stage, expected: stagedFingerprint),
              matchesIfPresent(facts.backup, expected: journal.backupFingerprint)
        else { return .block }

        let targetIsNew = facts.target.exists && facts.target.fingerprint == stagedFingerprint
        let targetIsOld = facts.target.exists
            && journal.backupFingerprint != nil
            && facts.target.fingerprint == journal.backupFingerprint

        switch facts.indexState {
        case .newEntryPresent:
            if targetIsNew { return .cleanup }
            if facts.target.exists { return .block }
            if facts.stage.exists { return .rollForwardTarget }
            return .block

        case .expectedEntryPresent:
            if targetIsNew {
                return .commitIndex
            }
            if targetIsOld {
                return .cleanup
            }
            if facts.target.exists {
                return .block
            }
            if facts.backup.exists {
                return .restoreBackup
            }
            if facts.stage.exists,
               journal.kind == .missingTargetRepair
            {
                return .rollForwardTarget
            }
            return .block

        case .neither:
            switch journal.kind {
            case .newImport:
                if targetIsNew {
                    return .commitIndex
                }
                if facts.target.exists {
                    return .block
                }
                return facts.stage.exists ? .rollForwardTarget : .cleanup
            case .orphanAdopt:
                if targetIsNew {
                    return .commitIndex
                }
                if facts.target.exists {
                    return targetIsOld ? .cleanup : .block
                }
                if facts.stage.exists {
                    return .rollForwardTarget
                }
                return facts.backup.exists ? .restoreBackup : .cleanup
            case .indexedReplace, .missingTargetRepair:
                if targetIsNew {
                    return .removeUncommittedTarget
                }
                if facts.target.exists {
                    return .block
                }
                return facts.backup.exists ? .restoreBackup : .block
            case .unclassified:
                return .block
            }

        case .conflicting:
            return .block
        }
    }

    private static func matchesIfPresent(
        _ observed: SongLibraryObservedTransactionFile,
        expected: TransactionFileFingerprint?
    ) -> Bool {
        guard observed.exists else { return true }
        return expected != nil && observed.fingerprint == expected
    }

    private static func hasNoAliasedPaths(_ facts: SongLibraryTransactionRecoveryFacts) -> Bool {
        let existingFiles = [facts.stage, facts.backup, facts.target].filter(\.exists)
        let identifiers = existingFiles.compactMap(\.resourceIdentifier)
        guard existingFiles.count < 2 || identifiers.count == existingFiles.count else {
            return false
        }
        return Set(identifiers).count == identifiers.count
    }
}
