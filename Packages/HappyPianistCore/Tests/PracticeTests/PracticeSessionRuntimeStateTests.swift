import Foundation
import MusicXML
@testable import Practice
import Testing

@MainActor
@Test
func runtimeStateKeepsTheFirstPlaybackFailureForTheCurrentRound() {
    let state = PracticeSessionRuntimeState()

    state.recordPlaybackError(RuntimeStateTestError.first)
    state.recordPlaybackError(RuntimeStateTestError.second)

    #expect(state.playbackErrorMessage == "first")
}

@Test
func progressCoordinatorRetainsPendingProgressAfterFinishFailure() async {
    let repository = RetryingProgressRepository()
    let coordinator = PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let session = await coordinator.begin(identity: identity)
    var progress = SongPracticeProgress(identity: identity, updatedAt: .now)
    progress.measureFacts = [
        MeasurePracticeFacts(
            sourceMeasureID: PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0),
            handMode: .both,
            successfulAttempts: 3
        ),
    ]
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

private enum RuntimeStateTestError: LocalizedError {
    case first
    case second

    var errorDescription: String? {
        switch self {
        case .first: "first"
        case .second: "second"
        }
    }
}

private enum RetryingProgressError: Error {
    case writeFailed
}

private actor RetryingProgressRepository: PracticeProgressRepositoryProtocol {
    private var values: [PracticeSongIdentity: SongPracticeProgress] = [:]
    private var writeError: Error? = RetryingProgressError.writeFailed
    private(set) var upsertCount = 0

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument(songs: Array(values.values)))
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        values[identity]
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(songID: songID, progresses: [], scoreMetadata: [], sessions: []))
    }

    func upsert(_ progress: SongPracticeProgress) throws {
        if let writeError { throw writeError }
        upsertCount += 1
        values[progress.identity] = progress
    }

    func upsert(_: SongScorePracticeMetadata) {}

    func remove(songID: UUID) {
        values = values.filter { $0.key.songID != songID }
    }

    func allowWrites() {
        writeError = nil
    }
}
