import Foundation

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
