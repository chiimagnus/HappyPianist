import Foundation
@testable import HappyPianistAVP
import Testing

private actor RecordingProgressRepository: PracticeProgressRepositoryProtocol {
    private(set) var removedSongIDs: [UUID] = []
    var removalError: Error?

    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }
    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? { nil }
    func upsert(_: SongPracticeProgress) {}
    func remove(songID: UUID) throws {
        if let removalError { throw removalError }
        removedSongIDs.append(songID)
    }
}

@Test
@MainActor
func deletingSongBestEffortRemovesPracticeProgress() async {
    let songID = UUID()
    let entry = SongLibraryEntry(
        id: songID,
        displayName: "User Song",
        musicXMLFileName: "user.musicxml",
        importedAt: .now,
        audioFileName: nil
    )
    let repository = RecordingProgressRepository()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: songID),
        practiceProgressRepository: repository
    )

    await viewModel.deleteEntry(entryID: songID)

    #expect(viewModel.index.entries.isEmpty)
    #expect(await repository.removedSongIDs == [songID])
}
