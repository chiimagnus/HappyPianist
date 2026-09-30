import Foundation
import Library
import MusicXML
import Practice

protocol SongPracticeLibrarySnapshotBuilding: Sendable {
    @concurrent
    nonisolated func build(
        entry: SongLibraryEntry,
        historyResult: PracticeSongHistoryLoadResult,
        viewedAt: Date,
        viewingTimeZone: TimeZone,
        canResetCorruption: Bool
    ) async -> SongPracticeLibraryPresentationState
}

struct SongPracticeLibrarySnapshotBuilder: SongPracticeLibrarySnapshotBuilding {
    private let isolationObserver: (@Sendable ((any Actor)?) -> Void)?

    init(isolationObserver: (@Sendable ((any Actor)?) -> Void)? = nil) {
        self.isolationObserver = isolationObserver
    }

    @concurrent
    nonisolated func build(
        entry: SongLibraryEntry,
        historyResult: PracticeSongHistoryLoadResult,
        viewedAt: Date,
        viewingTimeZone: TimeZone,
        canResetCorruption: Bool
    ) async -> SongPracticeLibraryPresentationState {
        let isolation: (any Actor)? = #isolation
        isolationObserver?(isolation)
        let identity = SongPracticeLibrarySelectionIdentity(
            songID: entry.id,
            scoreFileVersionID: entry.scoreFileVersionID
        )

        switch historyResult {
        case .unavailable:
            return .unavailable(SongPracticeLibraryUnavailable(
                identity: identity,
                reason: .temporarilyUnavailable,
                recoveryOptions: .retry
            ))
        case .corrupted:
            return .unavailable(SongPracticeLibraryUnavailable(
                identity: identity,
                reason: .corrupted,
                recoveryOptions: canResetCorruption ? .retryAndConfirmedBackupReset : .retry
            ))
        case let .loaded(history):
            return buildLoaded(
                entry: entry,
                identity: identity,
                history: history,
                viewedAt: viewedAt,
                viewingTimeZone: viewingTimeZone
            )
        }
    }

    private nonisolated func buildLoaded(
        entry: SongLibraryEntry,
        identity: SongPracticeLibrarySelectionIdentity,
        history: PracticeSongHistory,
        viewedAt: Date,
        viewingTimeZone: TimeZone
    ) -> SongPracticeLibraryPresentationState {
        let sessions = history.sessions.filter { $0.songID == entry.id }
        guard sessions.isEmpty == false else {
            return .invitation(identity)
        }

        let progresses = deduplicatedProgresses(
            history.progresses.filter { $0.identity.songID == entry.id }
        )
        let metadata = SongScorePracticeMetadataOrder.preferred(
            in: history.scoreMetadata.filter {
                $0.songID == entry.id && $0.scoreFileVersionID == entry.scoreFileVersionID
            }
        )
        let currentProgress = metadata.flatMap { metadata in
            PracticeProgressRecordOrder.preferred(
                in: progresses.filter { $0.identity.scoreRevision == metadata.scoreRevision }
            )
        }
        let uniqueCurrentFacts = SongPracticeMeasureFactOrder.uniqueRealFacts(
            in: currentProgress?.measureFacts ?? []
        )
        let sourceStates = Dictionary(grouping: uniqueCurrentFacts, by: \.sourceMeasureID)
            .mapValues(SongPracticeMeasureFactOrder.sourceState)
        let measureProgress = metadata.map { metadata in
            SongPracticeMeasureProgressState.available(
                deriveMeasureProgress(
                    states: sourceStates,
                    totalSourceMeasureCount: metadata.totalSourceMeasureCount
                )
            )
        } ?? .metadataUnavailable
        let resumeOccurrenceID = currentProgress?.resumePoint?.occurrenceID

        return .overview(SongPracticeLibraryOverview(
            identity: identity,
            status: overviewStatus(for: measureProgress),
            sessionSummary: SongPracticeSessionSummaryBuilder().build(
                songID: entry.id,
                sessions: sessions,
                viewedAt: viewedAt,
                viewingTimeZone: viewingTimeZone
            ),
            measureProgress: measureProgress,
            scoreRevision: metadata?.scoreRevision,
            sourceMeasureStates: sourceStates,
            resumeOccurrenceID: resumeOccurrenceID,
            focusMeasures: SongPracticeFocusMeasureBuilder().build(from: currentProgress)
        ))
    }

    private nonisolated func overviewStatus(
        for measureProgress: SongPracticeMeasureProgressState
    ) -> SongPracticeLibraryOverviewStatus {
        switch measureProgress {
        case .metadataUnavailable:
            .pending
        case let .available(progress)
            where progress.totalSourceMeasureCount > 0
            && progress.stableSourceMeasureCount == progress.totalSourceMeasureCount:
            .stable
        case .available:
            .learning
        }
    }

    private nonisolated func deduplicatedProgresses(
        _ progresses: [SongPracticeProgress]
    ) -> [SongPracticeProgress] {
        Dictionary(grouping: progresses, by: \.identity)
            .values
            .compactMap { PracticeProgressRecordOrder.preferred(in: $0) }
    }

    private nonisolated func deriveMeasureProgress(
        states: [PracticeSourceMeasureID: SongPracticeSourceMeasureState],
        totalSourceMeasureCount: Int
    ) -> SongPracticeMeasureProgress {
        let stableCount = min(totalSourceMeasureCount, states.values.filter { $0 == .stable }.count)
        let learningCount = min(
            max(0, totalSourceMeasureCount - stableCount),
            states.values.filter { $0 == .learning }.count
        )
        return SongPracticeMeasureProgress(
            stableSourceMeasureCount: stableCount,
            learningSourceMeasureCount: learningCount,
            unpracticedSourceMeasureCount: max(
                0,
                totalSourceMeasureCount - stableCount - learningCount
            )
        )
    }
}
