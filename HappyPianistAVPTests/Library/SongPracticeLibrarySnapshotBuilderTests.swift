import Foundation
@testable import HappyPianistAVP
import Testing

private let snapshotBuilder = SongPracticeLibrarySnapshotBuilder()
private let snapshotViewedAt = Date(timeIntervalSince1970: 1_721_044_800)
private let snapshotTimeZone = TimeZone(identifier: "Asia/Singapore")!

@Test
@MainActor
func snapshotBuilderLeavesMainActorIsolation() async {
    let entry = makeSnapshotEntry()
    let probe = SnapshotBuilderIsolationProbe()
    let builder = SongPracticeLibrarySnapshotBuilder { isolation in
        probe.record(isolation: isolation)
    }

    #expect(await buildSnapshot(
        builder: builder,
        entry: entry,
        history: PracticeSongHistory(songID: entry.id, progresses: [], scoreMetadata: [])
    ) == .invitation(snapshotIdentity(entry)))
    #expect(probe.observedNonisolated == true)
}

@Test
func invitationDependsOnSessionsNotMeasureAttempts() async {
    let entry = makeSnapshotEntry()
    let progress = makeSnapshotProgress(
        songID: entry.id,
        revision: "current",
        facts: [snapshotFact(0, hand: .both, state: .stable)]
    )

    #expect(await buildSnapshot(
        entry: entry,
        history: PracticeSongHistory(
            songID: entry.id,
            progresses: [progress],
            scoreMetadata: [makeSnapshotMetadata(entry: entry, revision: "current")]
        )
    ) == .invitation(snapshotIdentity(entry)))
}

@Test
func overviewUsesSessionsWhenCurrentMetadataIsUnavailable() async throws {
    let entry = makeSnapshotEntry()
    let session = try makeSnapshotSession(songID: entry.id, revision: "old", activeMilliseconds: 45_000)

    guard case let .overview(overview) = await buildSnapshot(
        entry: entry,
        history: PracticeSongHistory(
            songID: entry.id,
            progresses: [],
            scoreMetadata: [],
            sessions: [session]
        )
    ) else {
        Issue.record("Expected overview")
        return
    }

    #expect(overview.identity == snapshotIdentity(entry))
    #expect(overview.sessionSummary.sessionCount == 1)
    #expect(overview.sessionSummary.totalActiveDurationMilliseconds == 45_000)
    #expect(overview.measureProgress == .metadataUnavailable)
    #expect(overview.resumeSourceMeasureID == nil)
    #expect(overview.focusMeasures.isEmpty)
}

@Test
func overviewMergesCurrentRevisionHandsAndCompletesThreeWayTotal() async throws {
    let entry = makeSnapshotEntry()
    let revision = "current"
    let progress = makeSnapshotProgress(
        songID: entry.id,
        revision: revision,
        facts: [
            snapshotFact(0, hand: .both, state: .stable),
            snapshotFact(1, hand: .left, state: .stable),
            snapshotFact(1, hand: .right, state: .stable),
            snapshotFact(2, hand: .left, state: .stable),
            snapshotFact(3, hand: .both, state: .learning, failed: 2),
        ]
    )
    let session = try makeSnapshotSession(songID: entry.id, revision: revision)

    guard case let .overview(overview) = await buildSnapshot(
        entry: entry,
        history: PracticeSongHistory(
            songID: entry.id,
            progresses: [progress],
            scoreMetadata: [makeSnapshotMetadata(entry: entry, revision: revision, total: 5)],
            sessions: [session]
        )
    ) else {
        Issue.record("Expected overview")
        return
    }

    #expect(overview.measureProgress == .available(SongPracticeMeasureProgress(
        stableSourceMeasureCount: 2,
        learningSourceMeasureCount: 2,
        unpracticedSourceMeasureCount: 1
    )))
}

@Test
func overviewWithMetadataAndNoFactsMarksEveryMeasureUnpracticed() async throws {
    let entry = makeSnapshotEntry()
    let session = try makeSnapshotSession(songID: entry.id, revision: "current")

    guard case let .overview(overview) = await buildSnapshot(
        entry: entry,
        history: PracticeSongHistory(
            songID: entry.id,
            progresses: [],
            scoreMetadata: [makeSnapshotMetadata(entry: entry, revision: "current", total: 8)],
            sessions: [session]
        )
    ) else {
        Issue.record("Expected overview")
        return
    }

    #expect(overview.measureProgress == .available(SongPracticeMeasureProgress(
        stableSourceMeasureCount: 0,
        learningSourceMeasureCount: 0,
        unpracticedSourceMeasureCount: 8
    )))
}

@Test
func overviewIsolatesResumeProgressAndFocusToCurrentRevision() async throws {
    let entry = makeSnapshotEntry()
    let oldSource = snapshotSource(9)
    let old = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: entry.id, scoreRevision: "old"),
        resumePoint: PracticeResumePoint(
            occurrenceID: PracticeMeasureOccurrenceID(sourceMeasureID: oldSource, occurrenceIndex: 0),
            stepIndex: 0,
            updatedAt: Date(timeIntervalSince1970: 20)
        ),
        measureFacts: [snapshotFact(9, hand: .both, state: .learning, issue: .wrongNote)],
        updatedAt: Date(timeIntervalSince1970: 20)
    )
    let currentSource = snapshotSource(1)
    let current = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: entry.id, scoreRevision: "current"),
        resumePoint: PracticeResumePoint(
            occurrenceID: PracticeMeasureOccurrenceID(sourceMeasureID: currentSource, occurrenceIndex: 0),
            stepIndex: 0,
            updatedAt: Date(timeIntervalSince1970: 30)
        ),
        measureFacts: [snapshotFact(1, hand: .both, state: .learning, failed: 3)],
        updatedAt: Date(timeIntervalSince1970: 30)
    )
    let sessions = [
        try makeSnapshotSession(songID: entry.id, revision: "old", startedAt: 100),
        try makeSnapshotSession(songID: entry.id, revision: "current", startedAt: 200),
    ]

    guard case let .overview(overview) = await buildSnapshot(
        entry: entry,
        history: PracticeSongHistory(
            songID: entry.id,
            progresses: [old, current],
            scoreMetadata: [makeSnapshotMetadata(entry: entry, revision: "current")],
            sessions: sessions
        )
    ) else {
        Issue.record("Expected overview")
        return
    }

    #expect(overview.sessionSummary.sessionCount == 2)
    #expect(overview.resumeSourceMeasureID == currentSource)
    #expect(overview.focusMeasures == [SongPracticeFocusMeasure(
        sourceMeasureID: currentSource,
        reason: .failedAttempts(3)
    )])
}

@Test
func overviewKeepsCurrentRevisionResumeBeforeTheDestinationMeasureHasFacts() async throws {
    let entry = makeSnapshotEntry()
    let attemptedSource = snapshotSource(0)
    let resumeSource = snapshotSource(1)
    let current = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: entry.id, scoreRevision: "current"),
        resumePoint: PracticeResumePoint(
            occurrenceID: PracticeMeasureOccurrenceID(
                sourceMeasureID: resumeSource,
                occurrenceIndex: 0
            ),
            stepIndex: 4,
            updatedAt: Date(timeIntervalSince1970: 30)
        ),
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: attemptedSource,
            handMode: .both,
            state: .learning,
            successfulAttempts: 1,
            lastAttemptAt: Date(timeIntervalSince1970: 20)
        )],
        updatedAt: Date(timeIntervalSince1970: 30)
    )

    guard case let .overview(overview) = await buildSnapshot(
        entry: entry,
        history: PracticeSongHistory(
            songID: entry.id,
            progresses: [current],
            scoreMetadata: [makeSnapshotMetadata(entry: entry, revision: "current")],
            sessions: [try makeSnapshotSession(songID: entry.id, revision: "current")]
        )
    ) else {
        Issue.record("Expected overview")
        return
    }

    #expect(overview.resumeSourceMeasureID == resumeSource)
}

@Test
func replacementKeepsStableSongSessionsWithoutLeakingOldRevisionFacts() async throws {
    let entry = makeSnapshotEntry(token: UUID())
    let oldToken = UUID()
    let oldSource = snapshotSource(7)
    let oldProgress = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: entry.id, scoreRevision: "old"),
        resumePoint: PracticeResumePoint(
            occurrenceID: PracticeMeasureOccurrenceID(
                sourceMeasureID: oldSource,
                occurrenceIndex: 0
            ),
            stepIndex: 0,
            updatedAt: Date(timeIntervalSince1970: 30)
        ),
        measureFacts: [snapshotFact(7, hand: .both, state: .learning, failed: 4)],
        updatedAt: Date(timeIntervalSince1970: 30)
    )
    let oldMetadata = SongScorePracticeMetadata(
        songID: entry.id,
        scoreFileVersionID: oldToken,
        scoreRevision: "old",
        totalSourceMeasureCount: 8,
        preparedAt: Date(timeIntervalSince1970: 30)
    )
    let oldSession = try makeSnapshotSession(songID: entry.id, revision: "old")

    guard case let .overview(overview) = await buildSnapshot(
        entry: entry,
        history: PracticeSongHistory(
            songID: entry.id,
            progresses: [oldProgress],
            scoreMetadata: [oldMetadata],
            sessions: [oldSession]
        )
    ) else {
        Issue.record("Expected replacement overview")
        return
    }

    #expect(overview.sessionSummary.sessionCount == 1)
    #expect(overview.measureProgress == .metadataUnavailable)
    #expect(overview.resumeSourceMeasureID == nil)
    #expect(overview.focusMeasures.isEmpty)
}

@Test
func unavailableCapabilitiesDistinguishIOFailureAndConfirmedCorruption() async {
    let entry = makeSnapshotEntry()

    #expect(await buildSnapshot(
        entry: entry,
        historyResult: .unavailable(description: "disk busy"),
        canResetCorruption: true
    ) == .unavailable(SongPracticeLibraryUnavailable(
        identity: snapshotIdentity(entry),
        reason: .temporarilyUnavailable,
        recoveryOptions: .retry
    )))
    #expect(await buildSnapshot(
        entry: entry,
        historyResult: .corrupted(description: "invalid JSON"),
        canResetCorruption: true
    ) == .unavailable(SongPracticeLibraryUnavailable(
        identity: snapshotIdentity(entry),
        reason: .corrupted,
        recoveryOptions: .retryAndConfirmedBackupReset
    )))
}

@Test
func snapshotBuildIsOrderIndependentForDuplicateProgressAndMetadata() async throws {
    let entry = makeSnapshotEntry(token: nil)
    let session = try makeSnapshotSession(songID: entry.id, revision: "b")
    let first = makeSnapshotProgress(
        songID: entry.id,
        revision: "a",
        facts: [snapshotFact(0, hand: .both, state: .stable)]
    )
    let second = makeSnapshotProgress(
        songID: entry.id,
        revision: "b",
        facts: [snapshotFact(1, hand: .both, state: .learning, failed: 1)]
    )
    let metadataA = makeSnapshotMetadata(entry: entry, revision: "a", preparedAt: 100)
    let metadataB = makeSnapshotMetadata(entry: entry, revision: "b", preparedAt: 100)
    let forward = PracticeSongHistory(
        songID: entry.id,
        progresses: [first, second],
        scoreMetadata: [metadataA, metadataB],
        sessions: [session]
    )
    let reversed = PracticeSongHistory(
        songID: entry.id,
        progresses: [second, first],
        scoreMetadata: [metadataB, metadataA],
        sessions: [session]
    )

    let forwardState = await buildSnapshot(entry: entry, history: forward)
    let reversedState = await buildSnapshot(entry: entry, history: reversed)
    #expect(forwardState == reversedState)
}

private func buildSnapshot(
    builder: SongPracticeLibrarySnapshotBuilder = snapshotBuilder,
    entry: SongLibraryEntry,
    history: PracticeSongHistory,
    canResetCorruption: Bool = false
) async -> SongPracticeLibraryPresentationState {
    await buildSnapshot(
        builder: builder,
        entry: entry,
        historyResult: .loaded(history),
        canResetCorruption: canResetCorruption
    )
}

private func buildSnapshot(
    builder: SongPracticeLibrarySnapshotBuilder = snapshotBuilder,
    entry: SongLibraryEntry,
    historyResult: PracticeSongHistoryLoadResult,
    canResetCorruption: Bool
) async -> SongPracticeLibraryPresentationState {
    await builder.build(
        entry: entry,
        historyResult: historyResult,
        viewedAt: snapshotViewedAt,
        viewingTimeZone: snapshotTimeZone,
        canResetCorruption: canResetCorruption
    )
}

private func makeSnapshotEntry(token: UUID? = UUID()) -> SongLibraryEntry {
    SongLibraryEntry(
        id: UUID(),
        displayName: "Song",
        musicXMLFileName: "song.musicxml",
        scoreFileVersionID: token,
        importedAt: Date(timeIntervalSince1970: 0),
        audioFileName: nil
    )
}

private func snapshotIdentity(_ entry: SongLibraryEntry) -> SongPracticeLibrarySelectionIdentity {
    SongPracticeLibrarySelectionIdentity(
        songID: entry.id,
        scoreFileVersionID: entry.scoreFileVersionID
    )
}

private func makeSnapshotMetadata(
    entry: SongLibraryEntry,
    revision: String,
    total: Int = 10,
    preparedAt: TimeInterval = 100
) -> SongScorePracticeMetadata {
    SongScorePracticeMetadata(
        songID: entry.id,
        scoreFileVersionID: entry.scoreFileVersionID,
        scoreRevision: revision,
        totalSourceMeasureCount: total,
        preparedAt: Date(timeIntervalSince1970: preparedAt)
    )
}

private func makeSnapshotProgress(
    songID: UUID,
    revision: String,
    facts: [MeasurePracticeFacts]
) -> SongPracticeProgress {
    SongPracticeProgress(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: revision),
        measureFacts: facts,
        updatedAt: Date(timeIntervalSince1970: 50)
    )
}

private func snapshotFact(
    _ index: Int,
    hand: PracticeHandMode,
    state: MeasureLearningState,
    issue: PracticeIssueKind? = nil,
    failed: Int = 0
) -> MeasurePracticeFacts {
    MeasurePracticeFacts(
        sourceMeasureID: snapshotSource(index),
        handMode: hand,
        state: state,
        successfulAttempts: state == .stable ? 1 : 0,
        failedAttempts: failed,
        recentIssue: issue,
        lastAttemptAt: Date(timeIntervalSince1970: Double(index + 1))
    )
}

private func snapshotSource(_ index: Int) -> PracticeSourceMeasureID {
    PracticeSourceMeasureID(
        partID: "P1",
        sourceMeasureIndex: index,
        sourceNumberToken: "\(index + 1)"
    )
}

private func makeSnapshotSession(
    songID: UUID,
    revision: String,
    startedAt: TimeInterval = 100,
    activeMilliseconds: Int64 = 10_000
) throws -> PracticeSessionRecord {
    let day = try #require(PracticeLocalDay(
        year: 2026,
        month: 7,
        day: 15,
        timeZoneIdentifier: "Asia/Singapore"
    ))
    return try #require(PracticeSessionRecord(
        id: UUID(),
        songID: songID,
        scoreRevision: revision,
        windowOpenedAt: Date(timeIntervalSince1970: startedAt - 10),
        practiceStartedAt: Date(timeIntervalSince1970: startedAt),
        practiceDay: day,
        endedAt: Date(timeIntervalSince1970: startedAt + 20),
        lastPersistedAt: Date(timeIntervalSince1970: startedAt + 20),
        practiceWindowDurationMilliseconds: max(20_000, activeMilliseconds),
        activePracticeDurationMilliseconds: activeMilliseconds,
        termination: .normal
    ))
}

private final class SnapshotBuilderIsolationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?

    var observedNonisolated: Bool? {
        lock.withLock { value }
    }

    func record(isolation: (any Actor)?) {
        lock.withLock { value = isolation == nil }
    }
}
