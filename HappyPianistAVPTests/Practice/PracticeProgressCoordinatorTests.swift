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

    var first = SongPracticeProgress(identity: identity, updatedAt: .distantPast)
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
    private let upsertError: Error?
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

    func upsert(_ progress: SongPracticeProgress) throws {
        if let upsertError { throw upsertError }
        upsertCount += 1
        values[progress.identity] = progress
    }

    func remove(songID: UUID) {
        values = values.filter { $0.key.songID != songID }
    }
}
