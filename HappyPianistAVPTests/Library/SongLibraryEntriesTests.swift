import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func libraryKeepsUserEntryThatSharesBundledDisplayName() {
    let sharedName = "Same Title"
    let bundled = SongLibraryEntry(
        id: UUID(),
        displayName: sharedName,
        musicXMLFileName: "bundled.musicxml",
        importedAt: .distantPast,
        audioFileName: nil,
        isBundled: true
    )
    let imported = SongLibraryEntry(
        id: UUID(),
        displayName: sharedName,
        musicXMLFileName: "imported.musicxml",
        importedAt: .now,
        audioFileName: nil
    )
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [imported], lastSelectedEntryID: nil),
        bundledEntries: [bundled]
    )

    #expect(viewModel.entries.map(\.id) == [bundled.id, imported.id])
}

@Test
@MainActor
func libraryDeduplicatesOnlyIdenticalEntryIDs() {
    let id = UUID()
    let bundled = SongLibraryEntry(
        id: id,
        displayName: "Bundled",
        musicXMLFileName: "bundled.musicxml",
        importedAt: .distantPast,
        audioFileName: nil,
        isBundled: true
    )
    let duplicateID = SongLibraryEntry(
        id: id,
        displayName: "Imported",
        musicXMLFileName: "imported.musicxml",
        importedAt: .now,
        audioFileName: nil
    )
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [duplicateID], lastSelectedEntryID: nil),
        bundledEntries: [bundled]
    )

    #expect(viewModel.entries == [bundled])
}
