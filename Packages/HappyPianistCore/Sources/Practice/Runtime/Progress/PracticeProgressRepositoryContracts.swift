import Foundation

public enum PracticeProgressLoadResult: Equatable, Sendable {
    case loaded(PracticeProgressDocument)
    case unavailable(description: String)
    case corrupted(description: String)
}

public enum PracticeProgressRepositoryError: Error, Equatable, Sendable {
    case unavailable(description: String)
    case corrupted(description: String)
}

public enum PracticeProgressRecoveryResult: Equatable, Sendable {
    case recovered(backupURL: URL)
    case notNeeded
}

public enum PracticeSessionMutationError: Error, Equatable, Sendable {
    case identityMismatch(id: UUID)
    case durationRegression(id: UUID)
    case cannotReopen(id: UUID)
}

public protocol PracticeProgressRepositoryProtocol: Sendable {
    func load() async -> PracticeProgressLoadResult
    func progress(for identity: PracticeSongIdentity) async -> SongPracticeProgress?
    func history(for songID: UUID) async -> PracticeSongHistoryLoadResult
    func upsert(_ progress: SongPracticeProgress) async throws
    func upsert(_ metadata: SongScorePracticeMetadata) async throws
    func remove(songID: UUID) async throws
}

public protocol PracticeProgressRecoveryProtocol: Sendable {
    func recoverFromCorruption() async throws -> PracticeProgressRecoveryResult
}

public protocol PracticeSessionRepositoryProtocol: Sendable {
    func upsert(_ session: PracticeSessionRecord) async throws
    func abandonLiveSession(id: UUID) async
}
