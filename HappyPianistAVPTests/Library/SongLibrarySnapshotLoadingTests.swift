import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func libraryLoadsNeverPracticedSnapshotWithoutScoreAccess() async throws {
    let entry = makeLoadingEntry()
    let repository = FixedHistoryRepository(histories: [
        entry.id: .loaded(PracticeSongHistory(
            songID: entry.id,
            progresses: [],
            scoreMetadata: []
        ))
    ])
    let fileStore = SnapshotScoreAccessSpy()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: entry.id),
        fileStore: fileStore,
        practiceProgressRepository: repository
    )

    try await waitForSnapshotState(viewModel) {
        $0 == .neverPracticed(selectionIdentity(entry))
    }

    #expect(await fileStore.scoreAccessCount == 0)
}

@Test
@MainActor
func libraryRejectsStaleSnapshotWhenSelectionChangesDuringHistoryRead() async throws {
    let first = makeLoadingEntry(name: "A")
    let second = makeLoadingEntry(name: "B")
    let repository = SuspendedHistoryRepository()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [first, second], lastSelectedEntryID: first.id),
        practiceProgressRepository: repository
    )
    await repository.waitForRequest(songID: first.id)

    viewModel.selectEntry(second.id)
    await repository.waitForRequest(songID: second.id)
    await repository.resume(songID: second.id, result: emptyHistory(for: second.id))
    try await waitForSnapshotState(viewModel) {
        $0 == .neverPracticed(selectionIdentity(second))
    }

    await repository.resume(songID: first.id, result: currentHistory(for: first))
    try await Task.sleep(for: .milliseconds(20))
    #expect(viewModel.practiceSnapshotState == .neverPracticed(selectionIdentity(second)))
}

@Test
@MainActor
func libraryAtoBtoAActorReadDisorderOnlyPublishesLatestA() async throws {
    let first = makeLoadingEntry(name: "A")
    let second = makeLoadingEntry(name: "B")
    let repository = OrderedSuspendedHistoryRepository()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [first, second], lastSelectedEntryID: first.id),
        practiceProgressRepository: repository
    )
    await repository.waitForRequestCount(1)

    viewModel.selectEntry(second.id)
    await repository.waitForRequestCount(2)
    viewModel.selectEntry(first.id)
    await repository.waitForRequestCount(3)

    await repository.resumeRequest(at: 2, result: emptyHistory(for: first.id))
    try await waitForSnapshotState(viewModel) {
        $0 == .neverPracticed(selectionIdentity(first))
    }
    await repository.resumeRequest(at: 1, result: currentHistory(for: second))
    await repository.resumeRequest(at: 0, result: currentHistory(for: first))
    try await Task.sleep(for: .milliseconds(20))

    #expect(viewModel.practiceSnapshotState == .neverPracticed(selectionIdentity(first)))
}

@Test
@MainActor
func libraryRefreshCoalescesSameSelectionAndReadsHistoryOnce() async throws {
    let entry = makeLoadingEntry()
    let repository = CountingHistoryRepository(result: emptyHistory(for: entry.id))
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: entry.id),
        practiceProgressRepository: repository,
        snapshotSettleDelay: .milliseconds(20)
    )

    viewModel.refreshSelectedPracticeSnapshot()
    viewModel.refreshSelectedPracticeSnapshot()
    try await waitForSnapshotState(viewModel) {
        $0 == .neverPracticed(selectionIdentity(entry))
    }

    #expect(await repository.historyRequestCount == 1)
}

@Test
@MainActor
func libraryReloadBindsSnapshotGenerationToChangedEntryToken() async throws {
    let songID = UUID()
    let first = makeLoadingEntry(id: songID, name: "Versioned", token: UUID())
    let second = makeLoadingEntry(id: songID, name: "Versioned", token: UUID())
    let indexStore = MutableSnapshotIndexStore(
        index: SongLibraryIndex(entries: [first], lastSelectedEntryID: songID)
    )
    let repository = FixedHistoryRepository(histories: [
        songID: currentHistory(for: second)
    ])
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [first], lastSelectedEntryID: songID),
        indexStore: indexStore,
        practiceProgressRepository: repository
    )
    await indexStore.replaceEntries([second])

    await viewModel.reload()
    try await waitForSnapshotState(viewModel) { state in
        guard case let .current(snapshot) = state else { return false }
        return snapshot.identity == selectionIdentity(second)
    }
}

@Test
@MainActor
func corruptedHistoryIsUnavailableWithoutGlobalErrorAndUsesTypedDiagnostic() async throws {
    let entry = makeLoadingEntry()
    let repository = FixedHistoryRepository(histories: [
        entry.id: .corrupted(description: "/Users/private/PracticeProgress/progress-v1.json")
    ])
    let diagnostics = SnapshotDiagnosticsRecorder()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: entry.id),
        practiceProgressRepository: repository,
        diagnosticsReporter: diagnostics
    )

    try await waitForSnapshotState(viewModel) {
        $0 == .unavailable(selectionIdentity(entry))
    }
    try await waitForDiagnostic(diagnostics)

    #expect(viewModel.errorMessage == nil)
    let event = try #require(await diagnostics.events.first)
    #expect(event.code == .libraryPracticeHistoryLoadFailed)
    #expect(event.songID == entry.id)
    #expect(event.reason.contains("/Users/") == false)
}

@Test
@MainActor
func rapidSelectionDragOnlyReadsFinalSongAfterSettleDelay() async throws {
    let first = makeLoadingEntry(name: "A")
    let second = makeLoadingEntry(name: "B")
    let third = makeLoadingEntry(name: "C")
    let repository = RequestedSongHistoryRepository()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(
            entries: [first, second, third],
            lastSelectedEntryID: first.id
        ),
        practiceProgressRepository: repository,
        snapshotSettleDelay: .milliseconds(20)
    )

    viewModel.selectEntry(second.id)
    viewModel.selectEntry(third.id)
    try await waitForSnapshotState(viewModel) {
        $0 == .neverPracticed(selectionIdentity(third))
    }

    #expect(await repository.requestedSongIDs == [third.id])
}

@Test
@MainActor
func refreshingSameSelectionReadsPracticeFactsWrittenWhileLibraryWasAway() async throws {
    let entry = makeLoadingEntry()
    let repository = UpdatingHistoryRepository(result: emptyHistory(for: entry.id))
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: entry.id),
        practiceProgressRepository: repository
    )
    try await waitForSnapshotState(viewModel) {
        $0 == .neverPracticed(selectionIdentity(entry))
    }

    await repository.setResult(currentHistory(for: entry))
    viewModel.refreshSelectedPracticeSnapshot()

    try await waitForSnapshotState(viewModel) {
        guard case let .current(snapshot) = $0 else { return false }
        return snapshot.identity == selectionIdentity(entry)
    }
}

@Test
@MainActor
func deletingSelectedSongLoadsFallbackSnapshot() async throws {
    let first = makeLoadingEntry(name: "A")
    let second = makeLoadingEntry(name: "B")
    let repository = FixedHistoryRepository(histories: [
        first.id: emptyHistory(for: first.id),
        second.id: emptyHistory(for: second.id),
    ])
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [first, second], lastSelectedEntryID: first.id),
        practiceProgressRepository: repository
    )

    await viewModel.deleteEntry(entryID: first.id)

    #expect(viewModel.selectedEntryID == second.id)
    try await waitForSnapshotState(viewModel) {
        $0 == .neverPracticed(selectionIdentity(second))
    }
}

@Test
@MainActor
func selectedSongRemainsImmediatelyAvailableWhileSnapshotHistoryIsSuspended() async {
    let entry = makeLoadingEntry()
    let repository = SuspendedHistoryRepository()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: entry.id),
        practiceProgressRepository: repository
    )
    await repository.waitForRequest(songID: entry.id)

    #expect(viewModel.selectedEntryID == entry.id)
    #expect(viewModel.practiceSnapshotState == .loading(selectionIdentity(entry)))

    await repository.resume(songID: entry.id, result: emptyHistory(for: entry.id))
}

@MainActor
private func waitForSnapshotState(
    _ viewModel: SongLibraryViewModel,
    matches: (SongPracticeLibraryPresentationState) -> Bool
) async throws {
    for _ in 0 ..< 200 {
        if matches(viewModel.practiceSnapshotState) { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for snapshot state: \(viewModel.practiceSnapshotState)")
}

private func waitForDiagnostic(_ recorder: SnapshotDiagnosticsRecorder) async throws {
    for _ in 0 ..< 200 {
        if await recorder.events.isEmpty == false { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for diagnostic")
}

private func makeLoadingEntry(
    id: UUID = UUID(),
    name: String = "Song",
    token: UUID? = UUID()
) -> SongLibraryEntry {
    SongLibraryEntry(
        id: id,
        displayName: name,
        musicXMLFileName: "\(name).musicxml",
        scoreFileVersionID: token,
        importedAt: Date(timeIntervalSince1970: 0),
        audioFileName: nil
    )
}

private func selectionIdentity(_ entry: SongLibraryEntry) -> SongPracticeLibrarySelectionIdentity {
    SongPracticeLibrarySelectionIdentity(
        songID: entry.id,
        scoreFileVersionID: entry.scoreFileVersionID
    )
}

private func emptyHistory(for songID: UUID) -> PracticeSongHistoryLoadResult {
    .loaded(PracticeSongHistory(songID: songID, progresses: [], scoreMetadata: []))
}

private func currentHistory(for entry: SongLibraryEntry) -> PracticeSongHistoryLoadResult {
    let revision = "r1"
    let date = Date(timeIntervalSince1970: 10)
    return .loaded(PracticeSongHistory(
        songID: entry.id,
        progresses: [SongPracticeProgress(
            identity: PracticeSongIdentity(songID: entry.id, scoreRevision: revision),
            measureFacts: [MeasurePracticeFacts(
                sourceMeasureID: PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0),
                handMode: .both,
                state: .learning,
                failedAttempts: 1,
                lastAttemptAt: date
            )],
            updatedAt: date
        )],
        scoreMetadata: [SongScorePracticeMetadata(
            songID: entry.id,
            scoreFileVersionID: entry.scoreFileVersionID,
            scoreRevision: revision,
            totalSourceMeasureCount: 1,
            preparedAt: date
        )]
    ))
}

private actor FixedHistoryRepository: PracticeProgressRepositoryProtocol {
    let histories: [UUID: PracticeSongHistoryLoadResult]

    init(histories: [UUID: PracticeSongHistoryLoadResult]) {
        self.histories = histories
    }

    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }
    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? { nil }
    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        histories[songID] ?? emptyHistory(for: songID)
    }
    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID _: UUID) {}
}

private actor SuspendedHistoryRepository: PracticeProgressRepositoryProtocol {
    private var continuations: [UUID: CheckedContinuation<PracticeSongHistoryLoadResult, Never>] = [:]

    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }
    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? { nil }
    func history(for songID: UUID) async -> PracticeSongHistoryLoadResult {
        await withCheckedContinuation { continuations[songID] = $0 }
    }
    func waitForRequest(songID: UUID) async {
        while continuations[songID] == nil { await Task.yield() }
    }
    func resume(songID: UUID, result: PracticeSongHistoryLoadResult) {
        continuations.removeValue(forKey: songID)?.resume(returning: result)
    }
    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID _: UUID) {}
}

private actor OrderedSuspendedHistoryRepository: PracticeProgressRepositoryProtocol {
    private struct Request {
        let continuation: CheckedContinuation<PracticeSongHistoryLoadResult, Never>
    }

    private var requests: [Request?] = []

    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }
    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? { nil }
    func history(for _: UUID) async -> PracticeSongHistoryLoadResult {
        await withCheckedContinuation { continuation in
            requests.append(Request(continuation: continuation))
        }
    }
    func waitForRequestCount(_ count: Int) async {
        while requests.count < count { await Task.yield() }
    }
    func resumeRequest(at index: Int, result: PracticeSongHistoryLoadResult) {
        guard requests.indices.contains(index), let request = requests[index] else { return }
        requests[index] = nil
        request.continuation.resume(returning: result)
    }
    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID _: UUID) {}
}

private actor CountingHistoryRepository: PracticeProgressRepositoryProtocol {
    let result: PracticeSongHistoryLoadResult
    private(set) var historyRequestCount = 0

    init(result: PracticeSongHistoryLoadResult) {
        self.result = result
    }

    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }
    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? { nil }
    func history(for _: UUID) -> PracticeSongHistoryLoadResult {
        historyRequestCount += 1
        return result
    }
    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID _: UUID) {}
}

private actor RequestedSongHistoryRepository: PracticeProgressRepositoryProtocol {
    private(set) var requestedSongIDs: [UUID] = []
    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }
    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? { nil }
    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        requestedSongIDs.append(songID)
        return emptyHistory(for: songID)
    }
    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID _: UUID) {}
}

private actor UpdatingHistoryRepository: PracticeProgressRepositoryProtocol {
    private var result: PracticeSongHistoryLoadResult
    init(result: PracticeSongHistoryLoadResult) { self.result = result }
    func setResult(_ result: PracticeSongHistoryLoadResult) { self.result = result }
    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }
    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? { nil }
    func history(for _: UUID) -> PracticeSongHistoryLoadResult { result }
    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID _: UUID) {}
}

private actor MutableSnapshotIndexStore: SongLibraryIndexStoreProtocol {
    private var index: SongLibraryIndex

    init(index: SongLibraryIndex) { self.index = index }
    func replaceEntries(_ entries: [SongLibraryEntry]) { index.entries = entries }
    func load() -> SongLibraryIndex { index }
    func setLastSelectedEntryID(_ entryID: UUID?) -> SongLibraryIndex {
        index.lastSelectedEntryID = entryID
        return index
    }
    func appendUserEntry(_ entry: SongLibraryEntry) -> SongLibraryIndex {
        index.entries.append(entry)
        return index
    }
    func removeUserEntry(
        id: UUID,
        fallbackLastSelectedEntryID: UUID?
    ) -> SongLibraryEntryMutationResult {
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == id }) else {
            return .notFound(index: index)
        }
        let entry = index.entries.remove(at: entryIndex)
        index.lastSelectedEntryID = fallbackLastSelectedEntryID
        return .applied(index: index, entry: entry)
    }
    func updateAudioFileName(
        entryID: UUID,
        expectedCurrentFileName: String?,
        newFileName: String?
    ) -> SongLibraryEntryMutationResult {
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

private actor SnapshotScoreAccessSpy: SongFileStoreProtocol {
    private(set) var scoreAccessCount = 0
    func scoreFileURL(fileName _: String) -> URL {
        scoreAccessCount += 1
        return URL(fileURLWithPath: "/unexpected")
    }
    func audioFileURL(fileName _: String) -> URL { URL(fileURLWithPath: "/audio") }
    func deleteScoreFile(named _: String) {}
    func deleteAudioFile(named _: String) {}
}

private actor SnapshotDiagnosticsRecorder: DiagnosticsReporting {
    private(set) var events: [DiagnosticEvent] = []
    func record(_ event: DiagnosticEvent) -> DiagnosticRecordResult {
        events.append(event)
        return DiagnosticRecordResult(persistedForExport: true)
    }
}
