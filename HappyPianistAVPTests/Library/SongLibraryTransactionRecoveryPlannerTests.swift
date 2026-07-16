import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func recoveryPlannerUsesObservedReplacementFactsAheadOfJournalPhase() throws {
    let staged = try recoveryFingerprint("a")
    let backup = try recoveryFingerprint("b")
    let journal = try recoveryJournal(staged: staged, backup: backup)

    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: journal,
            facts: recoveryFacts(
                backup: observed(backup, id: "backup"),
                target: observed(staged, id: "target"),
                index: .expectedEntryPresent
            )
        ) == .commitIndex
    )
    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: journal,
            facts: recoveryFacts(
                backup: observed(backup, id: "backup"),
                index: .expectedEntryPresent
            )
        ) == .restoreBackup
    )
    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: journal,
            facts: recoveryFacts(
                backup: observed(backup, id: "backup"),
                target: observed(staged, id: "target"),
                index: .newEntryPresent
            )
        ) == .cleanup
    )
}

@Test
func recoveryPlannerBlocksChangedOrAliasedFiles() throws {
    let staged = try recoveryFingerprint("a")
    let backup = try recoveryFingerprint("b")
    let changed = try recoveryFingerprint("c")
    let journal = try recoveryJournal(staged: staged, backup: backup)

    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: journal,
            facts: recoveryFacts(
                backup: observed(backup, id: "shared"),
                target: observed(changed, id: "target"),
                index: .expectedEntryPresent
            )
        ) == .block
    )
    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: journal,
            facts: recoveryFacts(
                stage: observed(staged, id: "shared"),
                backup: observed(backup, id: "shared"),
                index: .expectedEntryPresent
            )
        ) == .block
    )
}

@Test
func recoveryPlannerCleansUnclassifiedScratchWithoutTouchingExistingTarget() throws {
    let staged = try recoveryFingerprint("a")
    let journal = try SongLibraryImportJournal(
        operationID: UUID(),
        kind: .unclassified,
        phase: .staged,
        safeFileName: "score.musicxml",
        stagedFingerprint: staged
    )

    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: journal,
            facts: recoveryFacts(stage: observed(staged, id: "stage"), index: .neither)
        ) == .cleanup
    )
    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: journal,
            facts: recoveryFacts(target: observed(staged, id: "target"), index: .neither)
        ) == .cleanup
    )
    #expect(
        try SongLibraryTransactionRecoveryPlanner.action(
            journal: journal,
            facts: recoveryFacts(
                stage: observed(recoveryFingerprint("c"), id: "stage"),
                index: .neither
            )
        ) == .block
    )
}

@Test
func recoveryPlannerRollsForwardNewImportAndRemovesUncommittedReplacement() throws {
    let staged = try recoveryFingerprint("a")
    let newJournal = try recoveryJournal(kind: .newImport, staged: staged)
    let replacementJournal = try recoveryJournal(staged: staged, backup: recoveryFingerprint("b"))

    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: newJournal,
            facts: recoveryFacts(stage: observed(staged, id: "stage"), index: .neither)
        ) == .rollForwardTarget
    )
    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: newJournal,
            facts: recoveryFacts(target: observed(staged, id: "target"), index: .neither)
        ) == .commitIndex
    )
    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: replacementJournal,
            facts: recoveryFacts(target: observed(staged, id: "target"), index: .neither)
        ) == .removeUncommittedTarget
    )
}

@Test
func recoveryPlannerHandlesOrphanAndMissingTargetFaultPointsWithoutGuessing() throws {
    let staged = try recoveryFingerprint("a")
    let backup = try recoveryFingerprint("b")
    let orphan = try recoveryJournal(kind: .orphanAdopt, staged: staged, backup: backup)
    let missing = try recoveryJournal(kind: .missingTargetRepair, staged: staged)

    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: orphan,
            facts: recoveryFacts(
                stage: observed(staged, id: "stage"),
                backup: observed(backup, id: "backup"),
                index: .neither
            )
        ) == .rollForwardTarget
    )
    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: orphan,
            facts: recoveryFacts(
                backup: observed(backup, id: "backup"),
                index: .neither
            )
        ) == .restoreBackup
    )
    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: orphan,
            facts: recoveryFacts(
                backup: observed(backup, id: "backup"),
                target: observed(staged, id: "target"),
                index: .neither
            )
        ) == .commitIndex
    )
    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: missing,
            facts: recoveryFacts(
                stage: observed(staged, id: "stage"),
                index: .expectedEntryPresent
            )
        ) == .rollForwardTarget
    )
    #expect(
        SongLibraryTransactionRecoveryPlanner.action(
            journal: orphan,
            facts: recoveryFacts(
                stage: observed(staged, id: "stage"),
                backup: observed(backup, id: "backup"),
                index: .newEntryPresent
            )
        ) == .rollForwardTarget
    )
}

private func recoveryJournal(
    kind: SongLibraryImportOperationKind = .indexedReplace,
    staged: TransactionFileFingerprint,
    backup: TransactionFileFingerprint? = nil
) throws -> SongLibraryImportJournal {
    let songID = UUID()
    return try SongLibraryImportJournal(
        operationID: UUID(),
        kind: kind,
        phase: .targetInstalled,
        safeFileName: "score.musicxml",
        stagedFingerprint: staged,
        backupFingerprint: backup,
        expectedEntry: kind == .indexedReplace || kind == .missingTargetRepair
            ? SongLibraryExpectedEntryIdentity(
                songID: songID,
                scoreFileVersionID: UUID(),
                musicXMLFileName: "score.musicxml"
            )
            : nil,
        newEntry: SongLibraryNewEntryPayload(
            songID: songID,
            displayName: "Score",
            musicXMLFileName: "score.musicxml",
            importedAt: .now,
            scoreFileVersionID: UUID()
        )
    )
}

private func recoveryFacts(
    stage: SongLibraryObservedTransactionFile = .missing,
    backup: SongLibraryObservedTransactionFile = .missing,
    target: SongLibraryObservedTransactionFile = .missing,
    index: SongLibraryRecoveryIndexState
) -> SongLibraryTransactionRecoveryFacts {
    SongLibraryTransactionRecoveryFacts(
        stage: stage,
        backup: backup,
        target: target,
        indexState: index
    )
}

private func observed(
    _ fingerprint: TransactionFileFingerprint,
    id: String
) -> SongLibraryObservedTransactionFile {
    SongLibraryObservedTransactionFile(
        exists: true,
        fingerprint: fingerprint,
        resourceIdentifier: id
    )
}

private func recoveryFingerprint(_ character: Character) throws -> TransactionFileFingerprint {
    try TransactionFileFingerprint(byteCount: 1, sha256: String(repeating: character, count: 64))
}
