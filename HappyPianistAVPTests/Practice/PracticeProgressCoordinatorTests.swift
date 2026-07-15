import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func progressCoordinatorCoalescesCheckpointsAndFlushesLatestValue() async throws {
    let repository = InMemoryPracticeProgressRepository()
    let clock = FixedPracticeProgressClock(date: Date(timeIntervalSince1970: 200))
    let coordinator = PracticeProgressCoordinator(
        repository: repository,
        clock: clock,
        checkpointDelay: .seconds(60)
    )
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let session = await coordinator.begin(identity: identity)

    var first = SongPracticeProgress(identity: identity, updatedAt: clock.date)
    first.measureFacts = [makeFacts(successes: 1)]
    var second = first
    second.measureFacts = [makeFacts(successes: 2)]

    await coordinator.checkpoint(first, generation: session.generation)
    await coordinator.checkpoint(second, generation: session.generation)
    #expect(await coordinator.flush(generation: session.generation) == .saved)

    let saved = await repository.progress(for: identity)
    #expect(saved?.measureFacts.first?.successfulAttempts == 2)
    #expect(saved?.updatedAt == clock.date)
    #expect(await repository.upsertCount == 1)
}

@Test
func progressCoordinatorDiscardsLateGenerationWrites() async throws {
    let repository = InMemoryPracticeProgressRepository()
    let coordinator = PracticeProgressCoordinator(
        repository: repository,
        checkpointDelay: .seconds(60)
    )
    let firstIdentity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let firstSession = await coordinator.begin(identity: firstIdentity)
    let secondIdentity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r2")
    _ = await coordinator.begin(identity: secondIdentity)

    await coordinator.checkpoint(
        SongPracticeProgress(identity: firstIdentity, updatedAt: .now),
        generation: firstSession.generation
    )
    _ = await coordinator.flush(generation: firstSession.generation)

    #expect(await repository.progress(for: firstIdentity) == nil)
    #expect(await repository.upsertCount == 0)
}

@Test
func progressCoordinatorDiscardsLateBeginResult() async {
    let repository = SuspendedPracticeProgressRepository()
    let coordinator = PracticeProgressCoordinator(repository: repository)
    let firstIdentity = PracticeSongIdentity(songID: UUID(), scoreRevision: "first")
    let secondIdentity = PracticeSongIdentity(songID: UUID(), scoreRevision: "second")

    async let firstSession = coordinator.begin(identity: firstIdentity)
    await repository.waitForRequest(identity: firstIdentity)
    async let secondSession = coordinator.begin(identity: secondIdentity)
    await repository.waitForRequest(identity: secondIdentity)

    await repository.resume(identity: secondIdentity)
    let second = await secondSession
    await repository.resume(identity: firstIdentity)
    let first = await firstSession

    #expect(second.isCurrent)
    #expect(second.generation == 2)
    #expect(first.isCurrent == false)
    #expect(first.generation == 1)
}


@Test
func progressCoordinatorRejectsOlderSnapshotWithinSameGeneration() async throws {
    let repository = InMemoryPracticeProgressRepository()
    let coordinator = PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let session = await coordinator.begin(identity: identity)
    var newer = SongPracticeProgress(
        identity: identity,
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    newer.measureFacts = [makeFacts(successes: 2)]
    var older = newer
    older.updatedAt = Date(timeIntervalSince1970: 100)
    older.measureFacts = [makeFacts(successes: 1)]

    await coordinator.checkpoint(newer, generation: session.generation)
    await coordinator.checkpoint(older, generation: session.generation)
    _ = await coordinator.flush(generation: session.generation)

    #expect(await repository.progress(for: identity)?.measureFacts.first?.successfulAttempts == 2)
}

@Test
func progressCoordinatorRejectsSnapshotOlderThanTimestampedCheckpoint() async throws {
    let repository = InMemoryPracticeProgressRepository()
    let clock = FixedPracticeProgressClock(date: Date(timeIntervalSince1970: 300))
    let coordinator = PracticeProgressCoordinator(
        repository: repository,
        clock: clock,
        checkpointDelay: .seconds(60)
    )
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let session = await coordinator.begin(identity: identity)

    var first = SongPracticeProgress(
        identity: identity,
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    first.measureFacts = [makeFacts(successes: 3)]
    var stale = first
    stale.updatedAt = Date(timeIntervalSince1970: 200)
    stale.measureFacts = [makeFacts(successes: 1)]

    await coordinator.checkpoint(first, generation: session.generation)
    await coordinator.checkpoint(stale, generation: session.generation)
    _ = await coordinator.flush(generation: session.generation)

    let saved = await repository.progress(for: identity)
    #expect(saved?.updatedAt == clock.date)
    #expect(saved?.measureFacts.first?.successfulAttempts == 3)
}

@Test
func progressCoordinatorReportsStoreFailureWithoutCrashingSession() async throws {
    let repository = InMemoryPracticeProgressRepository(upsertError: TestProgressError.writeFailed)
    let coordinator = PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let session = await coordinator.begin(identity: identity)
    await coordinator.checkpoint(
        SongPracticeProgress(identity: identity, updatedAt: .now),
        generation: session.generation
    )

    guard case .failed = await coordinator.flush(generation: session.generation) else {
        Issue.record("Expected recoverable save failure")
        return
    }
}

@Test
func progressCoordinatorFinishFailureRetainsPendingProgressForRetry() async throws {
    let repository = InMemoryPracticeProgressRepository(upsertError: TestProgressError.writeFailed)
    let coordinator = PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let session = await coordinator.begin(identity: identity)
    var progress = SongPracticeProgress(identity: identity, updatedAt: .now)
    progress.measureFacts = [makeFacts(successes: 3)]
    await coordinator.checkpoint(progress, generation: session.generation)

    guard case .failed = await coordinator.finish(generation: session.generation) else {
        Issue.record("Expected recoverable finish failure")
        return
    }
    await repository.allowWrites()

    #expect(await coordinator.finish(generation: session.generation) == .saved)
    #expect(await repository.progress(for: identity)?.measureFacts.first?.successfulAttempts == 3)
    #expect(await repository.upsertCount == 1)
}

private func makeFacts(successes: Int) -> MeasurePracticeFacts {
    MeasurePracticeFacts(
        sourceMeasureID: PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0),
        handMode: .both,
        successfulAttempts: successes
    )
}

private enum TestProgressError: Error {
    case writeFailed
}

private struct FixedPracticeProgressClock: PracticeProgressClockProtocol {
    let date: Date
    func now() -> Date { date }
}

private actor InMemoryPracticeProgressRepository: PracticeProgressRepositoryProtocol {
    private var values: [PracticeSongIdentity: SongPracticeProgress]
    private var upsertError: Error?
    private(set) var upsertCount = 0

    init(
        values: [PracticeSongIdentity: SongPracticeProgress] = [:],
        upsertError: Error? = nil
    ) {
        self.values = values
        self.upsertError = upsertError
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument(songs: Array(values.values)))
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        values[identity]
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(
            songID: songID,
            progresses: values.values.filter { $0.identity.songID == songID },
            scoreMetadata: []
        ))
    }

    func allowWrites() {
        upsertError = nil
    }

    func upsert(_ progress: SongPracticeProgress) throws {
        if let upsertError { throw upsertError }
        upsertCount += 1
        values[progress.identity] = progress
    }

    func upsert(_: SongScorePracticeMetadata) {}

    func remove(songID: UUID) {
        values = values.filter { $0.key.songID != songID }
    }
}

private actor SuspendedPracticeProgressRepository: PracticeProgressRepositoryProtocol {
    private var continuations: [PracticeSongIdentity: CheckedContinuation<SongPracticeProgress?, Never>] = [:]

    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }

    func progress(for identity: PracticeSongIdentity) async -> SongPracticeProgress? {
        await withCheckedContinuation { continuation in
            continuations[identity] = continuation
        }
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(songID: songID, progresses: [], scoreMetadata: []))
    }

    func waitForRequest(identity: PracticeSongIdentity) async {
        while continuations[identity] == nil {
            await Task.yield()
        }
    }

    func resume(identity: PracticeSongIdentity) {
        continuations.removeValue(forKey: identity)?.resume(returning: nil)
    }

    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID _: UUID) {}
}
