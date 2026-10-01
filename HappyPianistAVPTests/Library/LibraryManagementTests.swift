import Foundation
@testable import HappyPianistAVP
import Library
import Testing

@MainActor struct LibraryManagementTests {
    @Test func rowAuditionAndAudioBindingDoNotChangeSpatialSelection() async {
        let selected = entry("Selected")
        let managed = entry("Managed")
        let library = SongLibraryViewModelTestHarness.make(index: SongLibraryIndex(entries: [selected, managed], lastSelectedEntryID: selected.id))
        await library.bindAudio(entryID: managed.id, from: URL(fileURLWithPath: "/tmp/managed.mp3"))
        #expect(library.selectedEntryID == selected.id)
        #expect(library.entries.first(where: { $0.id == managed.id })?.audioFileName != nil)
        await library.didTapListen(entryID: managed.id)
        #expect(library.currentListeningEntryID == managed.id)
        #expect(library.selectedEntryID == selected.id)
        library.stopListening()
    }

    @Test func rowDeletionPreservesDifferentSelectionAndEmptyListHasNoPhantomItem() async {
        let selected = entry("Selected")
        let managed = entry("Managed")
        let library = SongLibraryViewModelTestHarness.make(index: SongLibraryIndex(entries: [selected, managed], lastSelectedEntryID: selected.id))
        await library.deleteEntry(entryID: managed.id)
        #expect(library.selectedEntryID == selected.id)
        #expect(library.entries.map(\.id) == [selected.id])
        await library.deleteEntry(entryID: selected.id)
        #expect(library.entries.isEmpty)
        #expect(library.selectedEntryID == nil)
        #expect(SpatialLibraryVisibleSlice.items(orderedEntryIDs: library.entries.map(\.id), selectedEntryID: library.selectedEntryID).isEmpty)
    }

    @Test func bundledRowCannotDeleteOrBindAudio() async {
        var bundled = entry("Bundled")
        bundled.isBundled = true
        let library = SongLibraryViewModelTestHarness.make(index: .empty, bundledEntries: [bundled])
        await library.deleteEntry(entryID: bundled.id)
        #expect(library.entries == [bundled])
        await library.bindAudio(entryID: bundled.id, from: URL(fileURLWithPath: "/tmp/managed.mp3"))
        #expect(library.entries == [bundled])
        #expect(library.errorMessage != nil)
    }

    private func entry(_ name: String) -> SongLibraryEntry {
        SongLibraryEntry(id: UUID(), displayName: name, musicXMLFileName: "\(name).musicxml", scoreFileVersionID: UUID(), importedAt: .now, audioFileName: nil)
    }
}
