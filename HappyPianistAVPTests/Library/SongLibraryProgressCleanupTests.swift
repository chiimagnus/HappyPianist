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

@Test
@MainActor
func deletingSongUsesEntryReturnedByIndexActor() async {
    let songID = UUID()
    let cachedEntry = SongLibraryEntry(
        id: songID,
        displayName: "Cached",
        musicXMLFileName: "cached.musicxml",
        importedAt: .distantPast,
        audioFileName: "cached.mp3"
    )
    let persistedEntry = SongLibraryEntry(
        id: songID,
        displayName: "Persisted",
        musicXMLFileName: "persisted.musicxml",
        importedAt: .now,
        audioFileName: "persisted.mp3"
    )
    let store = DeletionIndexStore(
        index: SongLibraryIndex(entries: [persistedEntry], lastSelectedEntryID: songID)
    )
    let fileStore = DeletionRecordingFileStore()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [cachedEntry], lastSelectedEntryID: songID),
        indexStore: store,
        fileStore: fileStore
    )

    await viewModel.deleteEntry(entryID: songID)

    #expect(fileStore.deletedScoreNames == ["persisted.musicxml"])
    #expect(fileStore.deletedAudioNames == ["persisted.mp3"])
}

private actor DeletionIndexStore: SongLibraryIndexStoreProtocol {
    private var index: SongLibraryIndex

    init(index: SongLibraryIndex) {
        self.index = index
    }

    func load() throws -> SongLibraryIndex { index }

    func setLastSelectedEntryID(_ entryID: UUID?) throws -> SongLibraryIndex {
        index.lastSelectedEntryID = entryID
        return index
    }

    func appendUserEntry(_ entry: SongLibraryEntry) throws -> SongLibraryIndex {
        index.entries.append(entry)
        return index
    }

    func removeUserEntry(
        id: UUID,
        fallbackLastSelectedEntryID: UUID?
    ) throws -> SongLibraryEntryMutationResult {
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == id }) else {
            return .notFound(index: index)
        }
        let removedEntry = index.entries.remove(at: entryIndex)
        if index.lastSelectedEntryID == id {
            index.lastSelectedEntryID = fallbackLastSelectedEntryID
        }
        return .applied(index: index, entry: removedEntry)
    }

    func updateAudioFileName(
        entryID: UUID,
        expectedCurrentFileName: String?,
        newFileName: String?
    ) throws -> SongLibraryEntryMutationResult {
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == entryID }) else {
            return .notFound(index: index)
        }
        guard index.entries[entryIndex].audioFileName == expectedCurrentFileName else {
            return .conflict(index: index, entry: index.entries[entryIndex])
        }
        index.entries[entryIndex].audioFileName = newFileName
        return .applied(index: index, entry: index.entries[entryIndex])
    }
}

private final class DeletionRecordingFileStore: SongFileStoreProtocol {
    private(set) var deletedScoreNames: [String] = []
    private(set) var deletedAudioNames: [String] = []

    func importMusicXML(from _: URL) throws -> ImportedSongScoreFile {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func scoreFileURL(fileName: String) throws -> URL {
        URL(fileURLWithPath: fileName)
    }

    func audioFileURL(fileName: String) throws -> URL {
        URL(fileURLWithPath: fileName)
    }

    func deleteScoreFile(named fileName: String) throws {
        deletedScoreNames.append(fileName)
    }

    func deleteAudioFile(named fileName: String) throws {
        deletedAudioNames.append(fileName)
    }
}
