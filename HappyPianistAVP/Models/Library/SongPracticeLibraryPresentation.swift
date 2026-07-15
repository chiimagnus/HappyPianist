import Foundation

struct SongPracticeLibrarySelectionIdentity: Equatable, Sendable {
    let songID: UUID
    let scoreFileVersionID: UUID?
}

struct SongPracticeStreak: Equatable, Sendable {
    enum Recency: Equatable, Sendable {
        case current
        case recent
    }

    let dayCount: Int
    let recency: Recency
}

struct SongPracticeSessionSummary: Equatable, Sendable {
    let latestPracticeEndedAt: Date?
    let totalActiveDurationMilliseconds: Int64
    let sessionCount: Int
    let streak: SongPracticeStreak?
}

struct SongPracticeMeasureProgress: Equatable, Sendable {
    let stableSourceMeasureCount: Int
    let learningSourceMeasureCount: Int
    let unpracticedSourceMeasureCount: Int

    var totalSourceMeasureCount: Int {
        stableSourceMeasureCount + learningSourceMeasureCount + unpracticedSourceMeasureCount
    }
}

enum SongPracticeMeasureProgressState: Equatable, Sendable {
    case available(SongPracticeMeasureProgress)
    case metadataUnavailable
}

enum SongPracticeFocusReason: Equatable, Sendable {
    case recentIssue(PracticeIssueKind)
    case failedAttempts(Int)
    case learning
}

struct SongPracticeFocusMeasure: Equatable, Sendable {
    let sourceMeasureID: PracticeSourceMeasureID
    let reason: SongPracticeFocusReason
}

struct SongPracticeLibraryOverview: Equatable, Sendable {
    let identity: SongPracticeLibrarySelectionIdentity
    let sessionSummary: SongPracticeSessionSummary
    let measureProgress: SongPracticeMeasureProgressState
    let resumeSourceMeasureID: PracticeSourceMeasureID?
    let focusMeasures: [SongPracticeFocusMeasure]
}

struct SongPracticeLibraryUnavailable: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case temporarilyUnavailable
        case corrupted
    }

    enum RecoveryOptions: Equatable, Sendable {
        case retry
        case retryAndConfirmedBackupReset
    }

    let identity: SongPracticeLibrarySelectionIdentity
    let reason: Reason
    let recoveryOptions: RecoveryOptions
}

enum SongPracticeLibraryPresentationState: Equatable, Sendable {
    case loading(SongPracticeLibrarySelectionIdentity)
    case invitation(SongPracticeLibrarySelectionIdentity)
    case overview(SongPracticeLibraryOverview)
    case unavailable(SongPracticeLibraryUnavailable)
}
