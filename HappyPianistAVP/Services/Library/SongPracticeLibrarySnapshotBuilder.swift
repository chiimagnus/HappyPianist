import Foundation

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
        let measureProgress = metadata.map { metadata in
            SongPracticeMeasureProgressState.available(
                deriveMeasureProgress(
                    facts: uniqueCurrentFacts,
                    totalSourceMeasureCount: metadata.totalSourceMeasureCount
                )
            )
        } ?? .metadataUnavailable
        let resumeSourceMeasureID = validResumeSourceMeasureID(
            progress: currentProgress,
            currentFacts: uniqueCurrentFacts
        )

        return .overview(SongPracticeLibraryOverview(
            identity: identity,
            sessionSummary: SongPracticeSessionSummaryBuilder().build(
                songID: entry.id,
                sessions: sessions,
                viewedAt: viewedAt,
                viewingTimeZone: viewingTimeZone
            ),
            measureProgress: measureProgress,
            resumeSourceMeasureID: resumeSourceMeasureID,
            focusMeasures: SongPracticeFocusMeasureBuilder().build(from: currentProgress)
        ))
    }

    private nonisolated func deduplicatedProgresses(
        _ progresses: [SongPracticeProgress]
    ) -> [SongPracticeProgress] {
        Dictionary(grouping: progresses, by: \.identity)
            .values
            .compactMap { PracticeProgressRecordOrder.preferred(in: $0) }
    }

    private nonisolated func deriveMeasureProgress(
        facts: [MeasurePracticeFacts],
        totalSourceMeasureCount: Int
    ) -> SongPracticeMeasureProgress {
        let sourceGroups = Dictionary(grouping: facts, by: \.sourceMeasureID)
        let stableSourceIDs = Set(sourceGroups.compactMap { sourceID, facts in
            let stableHands = Set(facts.filter { $0.state == .stable }.map(\.handMode))
            return stableHands.contains(.both) || (stableHands.contains(.left) && stableHands.contains(.right))
                ? sourceID
                : nil
        })
        let learningSourceIDs = Set(sourceGroups.keys).subtracting(stableSourceIDs)
        let stableCount = min(totalSourceMeasureCount, stableSourceIDs.count)
        let learningCount = min(
            max(0, totalSourceMeasureCount - stableCount),
            learningSourceIDs.count
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

    private nonisolated func validResumeSourceMeasureID(
        progress: SongPracticeProgress?,
        currentFacts: [MeasurePracticeFacts]
    ) -> PracticeSourceMeasureID? {
        guard let source = progress?.resumePoint?.occurrenceID.sourceMeasureID,
              currentFacts.contains(where: { $0.sourceMeasureID == source })
        else {
            return nil
        }
        return source
    }
}
