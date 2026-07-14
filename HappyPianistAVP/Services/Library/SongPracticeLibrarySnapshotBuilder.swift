import Foundation

protocol SongPracticeLibrarySnapshotBuilding: Sendable {
    @concurrent
    nonisolated func build(
        entry: SongLibraryEntry,
        history: PracticeSongHistory
    ) async -> SongPracticeLibrarySnapshotBuildResult
}

struct SongPracticeLibrarySnapshotBuilder: SongPracticeLibrarySnapshotBuilding {
    private let isolationObserver: (@Sendable ((any Actor)?) -> Void)?

    init(isolationObserver: (@Sendable ((any Actor)?) -> Void)? = nil) {
        self.isolationObserver = isolationObserver
    }

    @concurrent
    nonisolated func build(
        entry: SongLibraryEntry,
        history: PracticeSongHistory
    ) async -> SongPracticeLibrarySnapshotBuildResult {
        let isolation: (any Actor)? = #isolation
        isolationObserver?(isolation)
        let progresses = deduplicatedProgresses(
            history.progresses.filter { $0.identity.songID == entry.id }
        )
        let realHistoricalFacts = progresses.flatMap(\.measureFacts).filter(hasRealAttempt)
        guard let latestPracticeDate = realHistoricalFacts.compactMap(\.lastAttemptAt).max() else {
            return .neverPracticed
        }

        let metadata = SongScorePracticeMetadataOrder.preferred(
            in: history.scoreMetadata.filter {
                $0.songID == entry.id && $0.scoreFileVersionID == entry.scoreFileVersionID
            }
        )
        guard let metadata else {
            return .needsRebuild(historyDate: latestPracticeDate)
        }

        let identity = SongPracticeLibrarySelectionIdentity(
            songID: entry.id,
            scoreFileVersionID: entry.scoreFileVersionID
        )
        let currentProgress = PracticeProgressRecordOrder.preferred(
            in: progresses.filter { $0.identity.scoreRevision == metadata.scoreRevision }
        )
        let currentFacts = currentProgress.flatMap(deriveCurrentFacts)

        return .current(SongPracticeLibrarySnapshot(
            identity: identity,
            status: currentFacts == nil ? .currentVersionNotPracticed : .practicedCurrentVersion,
            latestPracticeDate: latestPracticeDate,
            totalSourceMeasureCount: metadata.totalSourceMeasureCount,
            currentFacts: currentFacts,
            hasHistory: true
        ))
    }

    private nonisolated func deduplicatedProgresses(
        _ progresses: [SongPracticeProgress]
    ) -> [SongPracticeProgress] {
        Dictionary(grouping: progresses, by: \.identity)
            .values
            .compactMap { PracticeProgressRecordOrder.preferred(in: $0) }
    }

    private nonisolated func deriveCurrentFacts(
        _ progress: SongPracticeProgress
    ) -> SongPracticeCurrentFacts? {
        let realFacts = progress.measureFacts.filter(hasRealAttempt)
        guard realFacts.isEmpty == false else { return nil }

        let uniqueFacts = Dictionary(grouping: realFacts) {
            MeasureHandIdentity(sourceMeasureID: $0.sourceMeasureID, handMode: $0.handMode)
        }.values.compactMap(preferredFact)
        guard let currentFact = uniqueFacts.sorted(by: currentFactComesFirst).first else { return nil }
        let currentHandFacts = uniqueFacts.filter { $0.handMode == currentFact.handMode }

        let stableSourceIDs = Set(
            currentHandFacts.filter { $0.state == .stable }.map(\.sourceMeasureID)
        )
        let learningSourceIDs = Set(
            currentHandFacts.filter { $0.state == .learning }.map(\.sourceMeasureID)
        )
        let recentIssues = Dictionary(
            grouping: currentHandFacts.filter { $0.recentIssue != nil && $0.lastAttemptAt != nil },
            by: \.sourceMeasureID
        ).values.compactMap { facts -> SongPracticeRecentIssue? in
            guard let fact = preferredFact(facts),
                  let kind = fact.recentIssue,
                  let attemptedAt = fact.lastAttemptAt
            else { return nil }
            return SongPracticeRecentIssue(
                sourceMeasureID: fact.sourceMeasureID,
                kind: kind,
                attemptedAt: attemptedAt
            )
        }.sorted { lhs, rhs in
            if lhs.attemptedAt != rhs.attemptedAt { return lhs.attemptedAt > rhs.attemptedAt }
            return sourceComesFirst(lhs.sourceMeasureID, rhs.sourceMeasureID)
        }

        return SongPracticeCurrentFacts(
            handMode: currentFact.handMode,
            stableSourceMeasureCount: stableSourceIDs.count,
            learningSourceMeasureCount: learningSourceIDs.count,
            resumeSourceMeasureID: validResumeSourceMeasureID(
                progress: progress,
                currentFacts: uniqueFacts
            ),
            highestStableTempoScale: currentHandFacts
                .filter { $0.state == .stable }
                .compactMap(\.highestStableTempoScale)
                .max(),
            recentIssues: recentIssues
        )
    }

    private nonisolated func hasRealAttempt(_ fact: MeasurePracticeFacts) -> Bool {
        fact.lastAttemptAt != nil
    }

    private nonisolated func validResumeSourceMeasureID(
        progress: SongPracticeProgress,
        currentFacts: [MeasurePracticeFacts]
    ) -> PracticeSourceMeasureID? {
        guard let source = progress.resumePoint?.occurrenceID.sourceMeasureID,
              currentFacts.contains(where: { $0.sourceMeasureID == source })
        else { return nil }
        return source
    }

    private nonisolated func preferredFact(
        _ facts: [MeasurePracticeFacts]
    ) -> MeasurePracticeFacts? {
        facts.sorted(by: factComesFirst).first
    }

    private nonisolated func factComesFirst(
        _ lhs: MeasurePracticeFacts,
        _ rhs: MeasurePracticeFacts
    ) -> Bool {
        if lhs.lastAttemptAt != rhs.lastAttemptAt {
            return (lhs.lastAttemptAt ?? .distantPast) > (rhs.lastAttemptAt ?? .distantPast)
        }
        if statePriority(lhs.state) != statePriority(rhs.state) {
            return statePriority(lhs.state) > statePriority(rhs.state)
        }
        if lhs.successfulAttempts != rhs.successfulAttempts {
            return lhs.successfulAttempts > rhs.successfulAttempts
        }
        if lhs.failedAttempts != rhs.failedAttempts {
            return lhs.failedAttempts > rhs.failedAttempts
        }
        if lhs.consecutiveSuccesses != rhs.consecutiveSuccesses {
            return lhs.consecutiveSuccesses > rhs.consecutiveSuccesses
        }
        if lhs.highestStableTempoScale != rhs.highestStableTempoScale {
            return (lhs.highestStableTempoScale ?? 0) > (rhs.highestStableTempoScale ?? 0)
        }
        return (lhs.recentIssue?.rawValue ?? "") > (rhs.recentIssue?.rawValue ?? "")
    }

    private nonisolated func currentFactComesFirst(
        _ lhs: MeasurePracticeFacts,
        _ rhs: MeasurePracticeFacts
    ) -> Bool {
        if lhs.lastAttemptAt != rhs.lastAttemptAt {
            return (lhs.lastAttemptAt ?? .distantPast) > (rhs.lastAttemptAt ?? .distantPast)
        }
        if lhs.sourceMeasureID != rhs.sourceMeasureID {
            return sourceComesFirst(lhs.sourceMeasureID, rhs.sourceMeasureID)
        }
        return lhs.handMode.rawValue < rhs.handMode.rawValue
    }

    private nonisolated func statePriority(_ state: MeasureLearningState) -> Int {
        switch state {
        case .notStarted: 0
        case .learning: 1
        case .stable: 2
        }
    }

    private nonisolated func sourceComesFirst(
        _ lhs: PracticeSourceMeasureID,
        _ rhs: PracticeSourceMeasureID
    ) -> Bool {
        if lhs.partID != rhs.partID { return lhs.partID < rhs.partID }
        if lhs.sourceMeasureIndex != rhs.sourceMeasureIndex {
            return lhs.sourceMeasureIndex < rhs.sourceMeasureIndex
        }
        return switch (lhs.sourceNumberToken, rhs.sourceNumberToken) {
        case (nil, .some): true
        case (.some, nil): false
        case let (.some(lhsToken), .some(rhsToken)): lhsToken < rhsToken
        case (nil, nil): false
        }
    }
}

private struct MeasureHandIdentity: Hashable, Sendable {
    let sourceMeasureID: PracticeSourceMeasureID
    let handMode: PracticeHandMode
}
