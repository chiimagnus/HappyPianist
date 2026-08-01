import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func importConflictClassifierUsesExactNamesUnlessVolumeFactsProveIdentity() {
    let entry = conflictEntry(fileName: "Prelude.musicxml")

    #expect(
        SongLibraryImportConflictClassifier.classify(
            userEntries: [entry],
            candidateFileName: "prelude.musicxml",
            targetFacts: SongLibraryImportTargetVolumeFacts(
                candidateExists: true,
                candidateResourceIdentifier: "resource-1",
                fileNamesWithCandidateResourceIdentifier: []
            )
        ) == .filesystemOrphan
    )
    #expect(
        SongLibraryImportConflictClassifier.classify(
            userEntries: [entry],
            candidateFileName: "prelude.musicxml",
            targetFacts: SongLibraryImportTargetVolumeFacts(
                candidateExists: true,
                candidateResourceIdentifier: "resource-1",
                fileNamesWithCandidateResourceIdentifier: ["Prelude.musicxml"]
            )
        ) == .indexedTarget(entry: entry)
    )
}

@Test
func importConflictClassifierDoesNotGuessUnicodeNormalization() {
    let decomposed = "Cafe\u{301}.musicxml"
    let composed = "Café.musicxml"
    let entry = conflictEntry(fileName: decomposed)

    #expect(
        SongLibraryImportConflictClassifier.classify(
            userEntries: [entry],
            candidateFileName: composed,
            targetFacts: SongLibraryImportTargetVolumeFacts(
                candidateExists: true,
                candidateResourceIdentifier: "resource-2",
                fileNamesWithCandidateResourceIdentifier: []
            )
        ) == .filesystemOrphan
    )
    #expect(
        SongLibraryImportConflictClassifier.classify(
            userEntries: [entry],
            candidateFileName: composed,
            targetFacts: SongLibraryImportTargetVolumeFacts(
                candidateExists: true,
                candidateResourceIdentifier: "resource-2",
                fileNamesWithCandidateResourceIdentifier: [decomposed]
            )
        ) == .indexedTarget(entry: entry)
    )
}

@Test
func importConflictClassifierDistinguishesMissingOrphanAndAmbiguousTargets() {
    let first = conflictEntry(fileName: "same.musicxml")
    let second = conflictEntry(fileName: "alias.musicxml")
    let bundled = SongLibraryEntry(
        id: UUID(),
        displayName: "Bundled",
        musicXMLFileName: "same.musicxml",
        scoreFileVersionID: UUID(),
        importedAt: .now,
        audioFileName: nil,
        isBundled: true
    )

    #expect(
        SongLibraryImportConflictClassifier.classify(
            userEntries: [bundled, first],
            candidateFileName: "same.musicxml",
            targetFacts: SongLibraryImportTargetVolumeFacts(
                candidateExists: false,
                candidateResourceIdentifier: nil,
                fileNamesWithCandidateResourceIdentifier: []
            )
        ) == .indexedMissingTarget(entry: first)
    )
    #expect(
        SongLibraryImportConflictClassifier.classify(
            userEntries: [first, second],
            candidateFileName: "same.musicxml",
            targetFacts: SongLibraryImportTargetVolumeFacts(
                candidateExists: true,
                candidateResourceIdentifier: "resource-3",
                fileNamesWithCandidateResourceIdentifier: ["same.musicxml", "alias.musicxml"]
            )
        ) == .ambiguousIndexedTargets(entries: [first, second])
    )
}

@Test
func importJournalRejectsInvalidDigestAndContainsNoURLField() throws {
    #expect(throws: SongLibraryImportTransactionModelError.invalidFingerprint) {
        _ = try TransactionFileFingerprint(byteCount: 1, sha256: "ABC")
    }
    let fingerprint = try conflictFingerprint("a")
    let journal = try SongLibraryImportJournal(
        operationID: UUID(),
        kind: .unclassified,
        phase: .staged,
        safeFileName: "score.musicxml",
        stagedFingerprint: fingerprint
    )
    let text = try String(decoding: JSONEncoder().encode(journal), as: UTF8.self)

    #expect(text.localizedStandardContains("url") == false)
    #expect(text.localizedStandardContains("path") == false)
    #expect(text.localizedStandardContains("score data") == false)
}

private func conflictEntry(fileName: String) -> SongLibraryEntry {
    SongLibraryEntry(
        id: UUID(),
        displayName: fileName,
        musicXMLFileName: fileName,
        scoreFileVersionID: UUID(),
        importedAt: .now,
        audioFileName: nil
    )
}

private func conflictFingerprint(_ character: Character) throws -> TransactionFileFingerprint {
    try TransactionFileFingerprint(byteCount: 1, sha256: String(repeating: character, count: 64))
}
