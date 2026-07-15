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
