import Foundation
@testable import HappyPianistAVP
import Testing

private actor RecordingProgressRepository: PracticeProgressRepositoryProtocol {
    private(set) var removedSongIDs: [UUID] = []
    private let removalError: PracticeProgressRepositoryError?

    init(removalError: PracticeProgressRepositoryError? = nil) {
        self.removalError = removalError
    }

    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }
    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? { nil }
    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(songID: songID, progresses: [], scoreMetadata: []))
    }
    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID: UUID) throws {
        if let removalError { throw removalError }
        removedSongIDs.append(songID)
    }
}

@Test
@MainActor
func deletingSongRemovesSessionsProgressAndMetadataFromTheSharedRepository() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = FilePracticeProgressRepository(
        paths: PracticeProgressPaths(rootDirectoryURL: directory)
    )
    let songID = UUID()
    let entry = SongLibraryEntry(
        id: songID,
        displayName: "User Song",
        musicXMLFileName: "user.musicxml",
        scoreFileVersionID: UUID(),
        importedAt: .now,
        audioFileName: nil
    )
    let progress = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: "r1"),
        updatedAt: Date(timeIntervalSince1970: 10)
    )
    let metadata = SongScorePracticeMetadata(
        songID: songID,
        scoreFileVersionID: entry.scoreFileVersionID,
        scoreRevision: "r1",
        totalSourceMeasureCount: 1,
        preparedAt: Date(timeIntervalSince1970: 10)
    )
    let session = try cleanupSession(songID: songID)
    try await repository.upsert(progress)
    try await repository.upsert(metadata)
    try await repository.upsert(session)
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: songID),
        practiceProgressRepository: repository
    )

    await viewModel.deleteEntry(entryID: songID)

    #expect(await repository.history(for: songID) == .loaded(PracticeSongHistory(
        songID: songID,
        progresses: [],
        scoreMetadata: [],
        sessions: []
    )))
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

    #expect(await fileStore.deletedScoreNames == ["persisted.musicxml"])
    #expect(await fileStore.deletedAudioNames == ["persisted.mp3"])
}

@Test
@MainActor
func practiceCleanupFailureKeepsTheIndexDeletionAndReportsTheFailure() async {
    let songID = UUID()
    let entry = SongLibraryEntry(
        id: songID,
        displayName: "User Song",
        musicXMLFileName: "user.musicxml",
        importedAt: .now,
        audioFileName: nil
    )
    let repository = RecordingProgressRepository(
        removalError: .unavailable(description: "NSCocoaErrorDomain#640")
    )
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: songID),
        practiceProgressRepository: repository
    )

    await viewModel.deleteEntry(entryID: songID)

    #expect(viewModel.index.entries.isEmpty)
    #expect(viewModel.errorMessage?.contains("练习进度清理失败") == true)
}

private func cleanupSession(songID: UUID) throws -> PracticeSessionRecord {
    let day = try #require(PracticeLocalDay(
        year: 2026,
        month: 7,
        day: 15,
        timeZoneIdentifier: "Asia/Singapore"
    ))
    return try #require(PracticeSessionRecord(
        id: UUID(),
        songID: songID,
        scoreRevision: "r1",
        windowOpenedAt: Date(timeIntervalSince1970: 1),
        practiceStartedAt: Date(timeIntervalSince1970: 2),
        practiceDay: day,
        endedAt: Date(timeIntervalSince1970: 10),
        lastPersistedAt: Date(timeIntervalSince1970: 10),
        practiceWindowDurationMilliseconds: 9_000,
        activePracticeDurationMilliseconds: 8_000,
        termination: .normal
    ))
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

private actor DeletionRecordingFileStore: SongFileStoreProtocol {
    private(set) var deletedScoreNames: [String] = []
    private(set) var deletedAudioNames: [String] = []

    func scoreFileURL(fileName: String) async throws -> URL {
        URL(fileURLWithPath: fileName)
    }

    func audioFileURL(fileName: String) async throws -> URL {
        URL(fileURLWithPath: fileName)
    }

    func deleteScoreFile(named fileName: String) async throws {
        deletedScoreNames.append(fileName)
    }

    func deleteAudioFile(named fileName: String) async throws {
        deletedAudioNames.append(fileName)
    }
}
