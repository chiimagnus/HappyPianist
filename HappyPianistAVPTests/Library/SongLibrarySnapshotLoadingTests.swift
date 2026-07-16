import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func emptyLibraryHasNoPracticeSnapshotPresentation() {
    let viewModel = SongLibraryViewModelTestHarness.make(index: .empty)

    #expect(viewModel.selectedEntryID == nil)
    #expect(viewModel.practiceSnapshotState == nil)
}

@Test
@MainActor
func libraryLoadsInvitationWithoutScoreAccess() async throws {
    let entry = makeLoadingEntry()
    let repository = FixedHistoryRepository(histories: [
        entry.id: .loaded(PracticeSongHistory(
            songID: entry.id,
            progresses: [],
            scoreMetadata: [],
            sessions: []
        )),
    ])
    let fileStore = SnapshotScoreAccessSpy()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: entry.id),
        fileStore: fileStore,
        practiceProgressRepository: repository
    )

    try await waitForSnapshotState(viewModel) {
        $0 == .invitation(selectionIdentity(entry))
    }

    #expect(await fileStore.scoreAccessCount == 0)
}

@Test
@MainActor
func libraryRejectsStaleSnapshotWhenSelectionChangesDuringHistoryRead() async throws {
    let first = makeLoadingEntry(name: "A")
    let second = makeLoadingEntry(name: "B")
    let repository = SuspendedHistoryRepository()
    let diagnostics = SnapshotDiagnosticsRecorder()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [first, second], lastSelectedEntryID: first.id),
        practiceProgressRepository: repository,
        diagnosticsReporter: diagnostics
    )
    await repository.waitForRequest(songID: first.id)

    viewModel.selectEntry(second.id)
    await repository.waitForRequest(songID: second.id)
    await repository.resume(songID: second.id, result: emptyHistory(for: second.id))
    try await waitForSnapshotState(viewModel) {
        $0 == .invitation(selectionIdentity(second))
    }

    await repository.resume(songID: first.id, result: currentHistory(for: first))
    try await Task.sleep(for: .milliseconds(20))
    #expect(viewModel.practiceSnapshotState == .invitation(selectionIdentity(second)))
    try await waitForDiagnostic(diagnostics, code: .libraryPracticeHistoryAction)
    #expect(await diagnostics.events.contains {
        $0.reason == "action=staleResultDiscarded" && $0.songID == first.id
    })
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
        $0 == .invitation(selectionIdentity(first))
    }
    await repository.resumeRequest(at: 1, result: currentHistory(for: second))
    await repository.resumeRequest(at: 0, result: currentHistory(for: first))
    try await Task.sleep(for: .milliseconds(20))

    #expect(viewModel.practiceSnapshotState == .invitation(selectionIdentity(first)))
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
        $0 == .invitation(selectionIdentity(entry))
    }

    #expect(await repository.historyRequestCount == 1)
}

@Test
@MainActor
func committedReplacementBindsSnapshotGenerationToChangedEntryToken() async throws {
    let songID = UUID()
    let first = makeLoadingEntry(id: songID, name: "Versioned", token: UUID())
    let second = makeLoadingEntry(id: songID, name: "Versioned", token: UUID())
    let updatedIndex = SongLibraryIndex(entries: [second], lastSelectedEntryID: songID)
    let importService = CommittedSnapshotImportService(index: updatedIndex, entry: second)
    let repository = FixedHistoryRepository(histories: [
        songID: currentHistory(for: second),
    ])
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [first], lastSelectedEntryID: songID),
        importTransactionService: importService,
        practiceProgressRepository: repository
    )

    await viewModel.importMusicXML(from: [URL(fileURLWithPath: "/tmp/Versioned.musicxml")])
    try await waitForSnapshotState(viewModel) { state in
        guard case let .overview(overview) = state else { return false }
        return overview.identity == selectionIdentity(second)
    }
}

@Test
@MainActor
func corruptedHistoryIsUnavailableWithoutGlobalErrorAndUsesTypedDiagnostic() async throws {
    let entry = makeLoadingEntry()
    let repository = FixedHistoryRepository(histories: [
        entry.id: .corrupted(description: "/Users/private/PracticeProgress/progress-v1.json"),
    ])
    let diagnostics = SnapshotDiagnosticsRecorder()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: entry.id),
        practiceProgressRepository: repository,
        diagnosticsReporter: diagnostics
    )

    try await waitForSnapshotState(viewModel) {
        $0 == .unavailable(SongPracticeLibraryUnavailable(
            identity: selectionIdentity(entry),
            reason: .corrupted,
            recoveryOptions: .retry
        ))
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
func retryStartsANewGenerationAndPublishesTheReloadedState() async throws {
    let entry = makeLoadingEntry()
    let repository = UpdatingHistoryRepository(
        result: .unavailable(description: "NSCocoaErrorDomain#640")
    )
    let diagnostics = SnapshotDiagnosticsRecorder()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: entry.id),
        practiceProgressRepository: repository,
        diagnosticsReporter: diagnostics
    )
    try await waitForSnapshotState(viewModel) {
        $0 == .unavailable(SongPracticeLibraryUnavailable(
            identity: selectionIdentity(entry),
            reason: .temporarilyUnavailable,
            recoveryOptions: .retry
        ))
    }

    await repository.setResult(emptyHistory(for: entry.id))
    viewModel.retrySelectedPracticeSnapshot()

    try await waitForSnapshotState(viewModel) {
        $0 == .invitation(selectionIdentity(entry))
    }
    #expect(await repository.historyRequestCount == 2)
    try await waitForDiagnostic(diagnostics, code: .libraryPracticeHistoryAction)
    #expect(await diagnostics.events.contains { $0.reason == "action=retry" })
}

@Test
@MainActor
func confirmedCorruptionResetReloadsOnlyAfterRecoverySucceeds() async throws {
    let entry = makeLoadingEntry()
    let repository = ControlledSnapshotRecoveryRepository(
        initial: [entry.id: .corrupted(description: "invalid JSON")],
        recovered: [entry.id: emptyHistory(for: entry.id)],
        behavior: .succeeds
    )
    let diagnostics = SnapshotDiagnosticsRecorder()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: entry.id),
        practiceProgressRepository: repository,
        practiceProgressRecovery: repository,
        diagnosticsReporter: diagnostics
    )
    try await waitForSnapshotState(viewModel) {
        $0 == corruptedUnavailable(for: entry, canReset: true)
    }

    await viewModel.recoverCorruptedSelectedPracticeHistory()

    try await waitForSnapshotState(viewModel) {
        $0 == .invitation(selectionIdentity(entry))
    }
    #expect(await repository.recoveryCount == 1)
    #expect(await repository.historyRequestCount == 2)
    try await waitForDiagnostic(diagnostics, code: .practiceProgressStoreReset)
}

@Test
@MainActor
func failedCorruptionResetKeepsUnavailableAndDoesNotPublishInvitation() async throws {
    let entry = makeLoadingEntry()
    let repository = ControlledSnapshotRecoveryRepository(
        initial: [entry.id: .corrupted(description: "invalid JSON")],
        recovered: [entry.id: emptyHistory(for: entry.id)],
        behavior: .fails
    )
    let diagnostics = SnapshotDiagnosticsRecorder()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: entry.id),
        practiceProgressRepository: repository,
        practiceProgressRecovery: repository,
        diagnosticsReporter: diagnostics
    )
    try await waitForSnapshotState(viewModel) {
        $0 == corruptedUnavailable(for: entry, canReset: true)
    }

    await viewModel.recoverCorruptedSelectedPracticeHistory()

    #expect(viewModel.practiceSnapshotState == corruptedUnavailable(for: entry, canReset: true))
    #expect(await repository.recoveryCount == 1)
    #expect(await repository.historyRequestCount == 1)
    try await waitForDiagnostic(diagnostics, code: .libraryPracticeHistoryLoadFailed)
    #expect(await diagnostics.events.contains {
        $0.stage == "practiceHistoryRecovery" && $0.reason.contains("/Users/") == false
    })
}

@Test
@MainActor
func completedResetCannotResurrectASelectionThatChangedDuringRecovery() async throws {
    let first = makeLoadingEntry(name: "A")
    let second = makeLoadingEntry(name: "B")
    let repository = ControlledSnapshotRecoveryRepository(
        initial: [
            first.id: .corrupted(description: "invalid JSON"),
            second.id: emptyHistory(for: second.id),
        ],
        recovered: [
            first.id: emptyHistory(for: first.id),
            second.id: emptyHistory(for: second.id),
        ],
        behavior: .suspended
    )
    let diagnostics = SnapshotDiagnosticsRecorder()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [first, second], lastSelectedEntryID: first.id),
        practiceProgressRepository: repository,
        practiceProgressRecovery: repository,
        diagnosticsReporter: diagnostics
    )
    try await waitForSnapshotState(viewModel) {
        $0 == corruptedUnavailable(for: first, canReset: true)
    }

    let recoveryTask = Task { await viewModel.recoverCorruptedSelectedPracticeHistory() }
    await repository.waitForRecovery()
    viewModel.selectEntry(second.id)
    try await waitForSnapshotState(viewModel) {
        $0 == .invitation(selectionIdentity(second))
    }
    await repository.resumeRecovery()
    await recoveryTask.value

    #expect(viewModel.practiceSnapshotState == .invitation(selectionIdentity(second)))
    try await waitForDiagnostic(diagnostics, code: .libraryPracticeHistoryAction)
    #expect(await diagnostics.events.contains {
        $0.reason == "action=staleResultDiscarded" && $0.songID == first.id
    })
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
        $0 == .invitation(selectionIdentity(third))
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
        $0 == .invitation(selectionIdentity(entry))
    }

    await repository.setResult(currentHistory(for: entry))
    viewModel.refreshSelectedPracticeSnapshot()

    try await waitForSnapshotState(viewModel) {
        guard case let .overview(overview) = $0 else { return false }
        return overview.identity == selectionIdentity(entry)
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
        $0 == .invitation(selectionIdentity(second))
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
        if let state = viewModel.practiceSnapshotState, matches(state) { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for snapshot state: \(viewModel.practiceSnapshotState)")
}

private func waitForDiagnostic(
    _ recorder: SnapshotDiagnosticsRecorder,
    code: DiagnosticCode? = nil
) async throws {
    for _ in 0 ..< 200 {
        if await recorder.events.contains(where: { code == nil || $0.code == code }) { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for diagnostic")
}

private func makeLoadingEntry(
    id: UUID = UUID(),
    name: String = "Song",
    token: UUID = UUID()
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

private func corruptedUnavailable(
    for entry: SongLibraryEntry,
    canReset: Bool
) -> SongPracticeLibraryPresentationState {
    .unavailable(SongPracticeLibraryUnavailable(
        identity: selectionIdentity(entry),
        reason: .corrupted,
        recoveryOptions: canReset ? .retryAndConfirmedBackupReset : .retry
    ))
}

private func emptyHistory(for songID: UUID) -> PracticeSongHistoryLoadResult {
    .loaded(PracticeSongHistory(songID: songID, progresses: [], scoreMetadata: [], sessions: []))
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
        )],
        sessions: [makeLoadingSession(songID: entry.id, revision: revision)]
    ))
}

private func makeLoadingSession(songID: UUID, revision: String) -> PracticeSessionRecord {
    let day = PracticeLocalDay(
        year: 2026,
        month: 7,
        day: 15,
        timeZoneIdentifier: "Asia/Singapore"
    )!
    return PracticeSessionRecord(
        id: UUID(),
        songID: songID,
        scoreRevision: revision,
        windowOpenedAt: Date(timeIntervalSince1970: 0),
        practiceStartedAt: Date(timeIntervalSince1970: 1),
        practiceDay: day,
        endedAt: Date(timeIntervalSince1970: 10),
        lastPersistedAt: Date(timeIntervalSince1970: 10),
        practiceWindowDurationMilliseconds: 10000,
        activePracticeDurationMilliseconds: 5000,
        termination: .normal
    )!
}

private actor FixedHistoryRepository: PracticeProgressRepositoryProtocol {
    let histories: [UUID: PracticeSongHistoryLoadResult]

    init(histories: [UUID: PracticeSongHistoryLoadResult]) {
        self.histories = histories
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? {
        nil
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        histories[songID] ?? emptyHistory(for: songID)
    }

    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID _: UUID) {}
}

private actor SuspendedHistoryRepository: PracticeProgressRepositoryProtocol {
    private var continuations: [UUID: CheckedContinuation<PracticeSongHistoryLoadResult, Never>] = [:]

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? {
        nil
    }

    func history(for songID: UUID) async -> PracticeSongHistoryLoadResult {
        await withCheckedContinuation { continuations[songID] = $0 }
    }

    func waitForRequest(songID: UUID) async {
        while continuations[songID] == nil {
            await Task.yield()
        }
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

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? {
        nil
    }

    func history(for _: UUID) async -> PracticeSongHistoryLoadResult {
        await withCheckedContinuation { continuation in
            requests.append(Request(continuation: continuation))
        }
    }

    func waitForRequestCount(_ count: Int) async {
        while requests.count < count {
            await Task.yield()
        }
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

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? {
        nil
    }

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
    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? {
        nil
    }

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
    private(set) var historyRequestCount = 0
    init(result: PracticeSongHistoryLoadResult) {
        self.result = result
    }

    func setResult(_ result: PracticeSongHistoryLoadResult) {
        self.result = result
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? {
        nil
    }

    func history(for _: UUID) -> PracticeSongHistoryLoadResult {
        historyRequestCount += 1
        return result
    }

    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID _: UUID) {}
}

private actor ControlledSnapshotRecoveryRepository:
    PracticeProgressRepositoryProtocol,
    PracticeProgressRecoveryProtocol
{
    enum Behavior {
        case succeeds
        case fails
        case suspended
    }

    private var histories: [UUID: PracticeSongHistoryLoadResult]
    private let recoveredHistories: [UUID: PracticeSongHistoryLoadResult]
    private let behavior: Behavior
    private var recoveryContinuation: CheckedContinuation<Void, Never>?
    private(set) var historyRequestCount = 0
    private(set) var recoveryCount = 0

    init(
        initial: [UUID: PracticeSongHistoryLoadResult],
        recovered: [UUID: PracticeSongHistoryLoadResult],
        behavior: Behavior
    ) {
        histories = initial
        recoveredHistories = recovered
        self.behavior = behavior
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? {
        nil
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        historyRequestCount += 1
        return histories[songID] ?? emptyHistory(for: songID)
    }

    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID _: UUID) {}

    func recoverFromCorruption() async throws -> PracticeProgressRecoveryResult {
        recoveryCount += 1
        switch behavior {
        case .succeeds:
            break
        case .fails:
            throw PracticeProgressRepositoryError.unavailable(
                description: "/Users/private/PracticeProgress/progress-v1.json"
            )
        case .suspended:
            await withCheckedContinuation { recoveryContinuation = $0 }
        }
        histories = recoveredHistories
        return .recovered(backupURL: URL(fileURLWithPath: "/tmp/progress-backup.json"))
    }

    func waitForRecovery() async {
        while recoveryContinuation == nil {
            await Task.yield()
        }
    }

    func resumeRecovery() {
        recoveryContinuation?.resume()
        recoveryContinuation = nil
    }
}

private actor CommittedSnapshotImportService: SongLibraryImportTransactionServicing {
    private let descriptor = SongLibraryStagedImport(id: UUID(), fileName: "Versioned.musicxml")
    private let index: SongLibraryIndex
    private let entry: SongLibraryEntry

    init(index: SongLibraryIndex, entry: SongLibraryEntry) {
        self.index = index
        self.entry = entry
    }

    func recoverPendingTransactions() -> SongLibraryTransactionRecoveryResult {
        .recovered
    }

    func stageImports(from _: [URL]) -> SongLibraryImportBatchStageResult {
        SongLibraryImportBatchStageResult(items: [.staged(descriptor)], blocked: nil)
    }

    func process(operationID: UUID) -> SongLibraryImportProcessResult {
        guard operationID == descriptor.id else {
            return .blocked(SongLibraryBlockedImport(operationID: operationID, message: "unexpected operation"))
        }
        return .committed(index: index, entry: entry)
    }

    func confirm(operationID: UUID) -> SongLibraryImportProcessResult {
        .blocked(SongLibraryBlockedImport(operationID: operationID, message: "unexpected confirmation"))
    }

    func cancel(operationID _: UUID) -> Bool {
        true
    }
}

private actor SnapshotScoreAccessSpy: SongFileStoreProtocol {
    private(set) var scoreAccessCount = 0
    func scoreFileURL(fileName _: String) -> URL {
        scoreAccessCount += 1
        return URL(fileURLWithPath: "/unexpected")
    }

    func audioFileURL(fileName _: String) -> URL {
        URL(fileURLWithPath: "/audio")
    }

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
