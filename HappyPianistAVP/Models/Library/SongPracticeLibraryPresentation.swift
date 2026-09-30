import Foundation
import MusicXML
import Practice

struct SongPracticeLibrarySelectionIdentity: Equatable, Sendable {
    let songID: UUID
    let scoreFileVersionID: UUID
}

struct SongPracticeStreak: Equatable {
    enum Recency: Equatable {
        case current
        case recent
    }

    let dayCount: Int
    let recency: Recency
}

struct SongPracticeSessionSummary: Equatable {
    let latestPracticeEndedAt: Date?
    let totalActiveDurationMilliseconds: Int64
    let sessionCount: Int
    let streak: SongPracticeStreak?
}

struct SongPracticeMeasureProgress: Equatable {
    let stableSourceMeasureCount: Int
    let learningSourceMeasureCount: Int
    let unpracticedSourceMeasureCount: Int

    var totalSourceMeasureCount: Int {
        stableSourceMeasureCount + learningSourceMeasureCount + unpracticedSourceMeasureCount
    }
}

enum SongPracticeMeasureProgressState: Equatable {
    case available(SongPracticeMeasureProgress)
    case metadataUnavailable
}

enum SongPracticeFocusReason: Equatable {
    case recentIssue(PracticeIssueKind)
    case failedAttempts(Int)
    case learning
}

struct SongPracticeFocusMeasure: Equatable {
    let sourceMeasureID: PracticeSourceMeasureID
    let reason: SongPracticeFocusReason
}

enum SongPracticeLibraryOverviewStatus: Equatable {
    case learning
    case stable
    case pending
}

struct SongPracticeLibraryOverview: Equatable {
    let identity: SongPracticeLibrarySelectionIdentity
    let status: SongPracticeLibraryOverviewStatus
    let sessionSummary: SongPracticeSessionSummary
    let measureProgress: SongPracticeMeasureProgressState
    let scoreRevision: String?
    let sourceMeasureStates: [PracticeSourceMeasureID: SongPracticeSourceMeasureState]
    let resumeOccurrenceID: PracticeMeasureOccurrenceID?
    let focusMeasures: [SongPracticeFocusMeasure]

}

enum SongPracticeSourceMeasureState: Equatable {
    case stable
    case learning
}

struct SongPracticeLibraryUnavailable: Equatable {
    enum Reason: Equatable {
        case temporarilyUnavailable
        case corrupted
    }

    enum RecoveryOptions: Equatable {
        case retry
        case retryAndConfirmedBackupReset
    }

    let identity: SongPracticeLibrarySelectionIdentity
    let reason: Reason
    let recoveryOptions: RecoveryOptions
}

enum SongPracticeLibraryPresentationState: Equatable {
    case loading(SongPracticeLibrarySelectionIdentity)
    case invitation(SongPracticeLibrarySelectionIdentity)
    case overview(SongPracticeLibraryOverview)
    case unavailable(SongPracticeLibraryUnavailable)
}
