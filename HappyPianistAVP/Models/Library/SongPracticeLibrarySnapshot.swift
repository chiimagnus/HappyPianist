import Foundation

struct SongPracticeLibrarySelectionIdentity: Equatable, Sendable {
    let songID: UUID
    let scoreFileVersionID: UUID?
}

struct SongPracticeRecentIssue: Equatable, Sendable {
    let sourceMeasureID: PracticeSourceMeasureID
    let kind: PracticeIssueKind
    let attemptedAt: Date
}

struct SongPracticeCurrentFacts: Equatable, Sendable {
    let handMode: PracticeHandMode
    let stableSourceMeasureCount: Int
    let learningSourceMeasureCount: Int
    let unpracticedSourceMeasureCount: Int
    let resumeSourceMeasureID: PracticeSourceMeasureID?
    let highestStableTempoScale: Double?
    let recentIssues: [SongPracticeRecentIssue]
}

struct SongPracticeLibrarySnapshot: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case practicedCurrentVersion
        case currentVersionNotPracticed
    }

    let identity: SongPracticeLibrarySelectionIdentity
    let status: Status
    let latestPracticeDate: Date?
    let totalSourceMeasureCount: Int
    let measureProgress: SongPracticeMeasureProgressState
    let currentFacts: SongPracticeCurrentFacts?
    let hasHistory: Bool
}

enum SongPracticeLibrarySnapshotBuildResult: Equatable, Sendable {
    case neverPracticed
    case current(SongPracticeLibrarySnapshot)
    case needsRebuild(historyDate: Date?)
}

enum SongPracticeLibraryPresentationState: Equatable, Sendable {
    case loading(SongPracticeLibrarySelectionIdentity)
    case neverPracticed(SongPracticeLibrarySelectionIdentity)
    case current(SongPracticeLibrarySnapshot)
    case needsRebuild(SongPracticeLibrarySelectionIdentity, historyDate: Date?)
    case unavailable(SongPracticeLibrarySelectionIdentity)
}
