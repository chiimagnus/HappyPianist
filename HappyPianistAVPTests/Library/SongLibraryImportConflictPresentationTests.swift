import SwiftUI
@testable import HappyPianistAVP
import Testing

@Test
func importConflictPresentationsUseDistinctActionsAndDestructiveRolesOnlyForOverwrite() {
    let entry = SongLibraryEntry(
        id: UUID(),
        displayName: "Existing",
        musicXMLFileName: "same.musicxml",
        importedAt: .distantPast,
        audioFileName: nil
    )

    let replacement = SongLibraryImportConflictPresentation(
        conflict: .indexedTarget(entry: entry)
    )
    let repair = SongLibraryImportConflictPresentation(
        conflict: .indexedMissingTarget(entry: entry)
    )
    let orphan = SongLibraryImportConflictPresentation(conflict: .filesystemOrphan)
    let ambiguous = SongLibraryImportConflictPresentation(
        conflict: .ambiguousIndexedTargets(entries: [entry, entry])
    )

    #expect(replacement.actionTitle == "替换现有曲谱")
    #expect(replacement.actionRole == .destructive)
    #expect(repair.actionTitle == "修复缺失曲谱")
    #expect(repair.actionRole == nil)
    #expect(orphan.actionTitle == "替换并加入曲库")
    #expect(orphan.actionRole == .destructive)
    #expect(ambiguous.actionTitle == nil)
    #expect(ambiguous.message.contains("无法安全判断"))
}
