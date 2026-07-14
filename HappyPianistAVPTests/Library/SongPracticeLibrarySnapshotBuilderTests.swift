import Foundation
@testable import HappyPianistAVP
import Testing

private let snapshotBuilder = SongPracticeLibrarySnapshotBuilder()

@Test
@MainActor
func snapshotBuilderLeavesMainActorIsolation() async {
    let entry = makeSnapshotEntry()
    let probe = SnapshotBuilderIsolationProbe()
    let builder = SongPracticeLibrarySnapshotBuilder { isolation in
        probe.record(isolation: isolation)
    }

    #expect(await builder.build(
        entry: entry,
        history: PracticeSongHistory(songID: entry.id, progresses: [], scoreMetadata: [])
    ) == .neverPracticed)
    #expect(probe.observedNonisolated == true)
}

@Test
func snapshotNeverPracticedIgnoresUpdatedAtWithoutAttempts() async {
    let entry = makeSnapshotEntry()
    let progress = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: entry.id, scoreRevision: "r1"),
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: snapshotSource(0),
            handMode: .both,
            state: .learning,
            successfulAttempts: 2,
            lastAttemptAt: nil
        )],
        updatedAt: Date(timeIntervalSince1970: 500)
    )

    #expect(await snapshotBuilder.build(
        entry: entry,
        history: PracticeSongHistory(songID: entry.id, progresses: [progress], scoreMetadata: [])
    ) == .neverPracticed)
}

@Test
func snapshotNeedsRebuildWhenRealHistoryHasNoExactTokenMetadata() async {
    let entry = makeSnapshotEntry(token: UUID())
    let progress = makeSnapshotProgress(songID: entry.id, revision: "old", attemptedAt: 10)
    let mismatched = makeSnapshotMetadata(
        songID: entry.id,
        token: UUID(),
        revision: "old"
    )

    #expect(await snapshotBuilder.build(
        entry: entry,
        history: PracticeSongHistory(
            songID: entry.id,
            progresses: [progress],
            scoreMetadata: [mismatched]
        )
    ) == .needsRebuild(historyDate: Date(timeIntervalSince1970: 10)))
}

@Test
func bundledBuildTokenChangeDoesNotReuseOldMetadata() async {
    let songID = UUID()
    let oldToken = BundledSongLibraryProvider.scoreFileVersionID(
        fileName: "score.musicxml",
        bundleIdentifier: "com.example.HappyPianist",
        shortVersion: "1.0",
        buildVersion: "1"
    )
    let currentToken = BundledSongLibraryProvider.scoreFileVersionID(
        fileName: "score.musicxml",
        bundleIdentifier: "com.example.HappyPianist",
        shortVersion: "1.0",
        buildVersion: "2"
    )
    let entry = SongLibraryEntry(
        id: songID,
        displayName: "Bundled",
        musicXMLFileName: "score.musicxml",
        scoreFileVersionID: currentToken,
        importedAt: Date(timeIntervalSince1970: 0),
        audioFileName: nil,
        isBundled: true
    )
    let progress = makeSnapshotProgress(songID: songID, revision: "old", attemptedAt: 10)
    let metadata = makeSnapshotMetadata(songID: songID, token: oldToken, revision: "old")

    #expect(oldToken != currentToken)
    #expect(await snapshotBuilder.build(
        entry: entry,
        history: PracticeSongHistory(
            songID: songID,
            progresses: [progress],
            scoreMetadata: [metadata]
        )
    ) == .needsRebuild(historyDate: Date(timeIntervalSince1970: 10)))
}

@Test
func snapshotLegacyNilTokenOnlyMatchesNilMetadata() async {
    let entry = makeSnapshotEntry(token: nil)
    let progress = makeSnapshotProgress(songID: entry.id, revision: "legacy", attemptedAt: 10)
    let metadata = makeSnapshotMetadata(songID: entry.id, token: nil, revision: "legacy")

    guard case let .current(snapshot) = await snapshotBuilder.build(
        entry: entry,
        history: PracticeSongHistory(
            songID: entry.id,
            progresses: [progress],
            scoreMetadata: [metadata]
        )
    ) else {
        Issue.record("Expected current legacy snapshot")
        return
    }
    #expect(snapshot.identity.scoreFileVersionID == nil)
    #expect(snapshot.status == .practicedCurrentVersion)
}

@Test
func snapshotCurrentMetadataWithOnlyOldAttemptsDoesNotNeedRebuild() async {
    let entry = makeSnapshotEntry()
    let old = makeSnapshotProgress(songID: entry.id, revision: "old", attemptedAt: 20)
    let metadata = makeSnapshotMetadata(songID: entry.id, token: entry.scoreFileVersionID, revision: "current")

    guard case let .current(snapshot) = await snapshotBuilder.build(
        entry: entry,
        history: PracticeSongHistory(
            songID: entry.id,
            progresses: [old],
            scoreMetadata: [metadata]
        )
    ) else {
        Issue.record("Expected current-version snapshot")
        return
    }
    #expect(snapshot.status == .currentVersionNotPracticed)
    #expect(snapshot.currentFacts == nil)
    #expect(snapshot.latestPracticeDate == Date(timeIntervalSince1970: 20))
}

@Test
func snapshotKeepsUnknownMetadataTotalWithoutInventingProgress() async throws {
    let entry = makeSnapshotEntry()
    let progress = makeSnapshotProgress(songID: entry.id, revision: "r1", attemptedAt: 10)
    let metadata = makeSnapshotMetadata(
        songID: entry.id,
        token: entry.scoreFileVersionID,
        revision: "r1",
        total: 0
    )

    guard case let .current(snapshot) = await snapshotBuilder.build(
        entry: entry,
        history: PracticeSongHistory(
            songID: entry.id,
            progresses: [progress],
            scoreMetadata: [metadata]
        )
    ) else {
        Issue.record("Expected current snapshot")
        return
    }

    #expect(snapshot.totalSourceMeasureCount == 0)
    #expect(snapshot.currentFacts != nil)
}

@Test
func snapshotDerivesUniqueCurrentHandFactsIssuesTempoAndValidResume() async throws {
    let entry = makeSnapshotEntry()
    let revision = "current"
    let resumeOccurrence = PracticeMeasureOccurrenceID(
        sourceMeasureID: snapshotSource(1),
        occurrenceIndex: 4
    )
    let current = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: entry.id, scoreRevision: revision),
        resumePoint: PracticeResumePoint(
            occurrenceID: resumeOccurrence,
            stepIndex: 2,
            updatedAt: Date(timeIntervalSince1970: 20)
        ),
        measureFacts: [
            snapshotFact(0, hand: .right, state: .learning, attemptedAt: 10),
            snapshotFact(0, hand: .right, state: .stable, tempo: 0.8, attemptedAt: 20),
            snapshotFact(1, hand: .right, state: .learning, issue: .wrongNote, attemptedAt: 19),
            snapshotFact(2, hand: .left, state: .stable, tempo: 1, attemptedAt: 5),
        ],
        updatedAt: Date(timeIntervalSince1970: 20)
    )
    let old = makeSnapshotProgress(songID: entry.id, revision: "old", attemptedAt: 30)
    let metadata = makeSnapshotMetadata(
        songID: entry.id,
        token: entry.scoreFileVersionID,
        revision: revision,
        total: 3
    )

    guard case let .current(snapshot) = await snapshotBuilder.build(
        entry: entry,
        history: PracticeSongHistory(
            songID: entry.id,
            progresses: [current, old],
            scoreMetadata: [metadata]
        )
    ) else {
        Issue.record("Expected current snapshot")
        return
    }
    let facts = try #require(snapshot.currentFacts)
    #expect(snapshot.latestPracticeDate == Date(timeIntervalSince1970: 30))
    #expect(facts.handMode == .right)
    #expect(facts.stableSourceMeasureCount == 1)
    #expect(facts.learningSourceMeasureCount == 1)
    #expect(facts.highestStableTempoScale == 0.8)
    #expect(facts.resumeSourceMeasureID == snapshotSource(1))
    #expect(facts.recentIssues == [SongPracticeRecentIssue(
        sourceMeasureID: snapshotSource(1),
        kind: .wrongNote,
        attemptedAt: Date(timeIntervalSince1970: 19)
    )])
}

@Test
func snapshotHidesResumeWithoutRealCurrentSourceFact() async throws {
    let entry = makeSnapshotEntry()
    let progress = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: entry.id, scoreRevision: "r1"),
        resumePoint: PracticeResumePoint(
            occurrenceID: PracticeMeasureOccurrenceID(
                sourceMeasureID: snapshotSource(9),
                occurrenceIndex: 9
            ),
            stepIndex: 0,
            updatedAt: Date(timeIntervalSince1970: 10)
        ),
        measureFacts: [snapshotFact(0, hand: .both, state: .learning, attemptedAt: 10)],
        updatedAt: Date(timeIntervalSince1970: 10)
    )
    let metadata = makeSnapshotMetadata(songID: entry.id, token: entry.scoreFileVersionID, revision: "r1")

    guard case let .current(snapshot) = await snapshotBuilder.build(
        entry: entry,
        history: PracticeSongHistory(
            songID: entry.id,
            progresses: [progress],
            scoreMetadata: [metadata]
        )
    ) else {
        Issue.record("Expected current snapshot")
        return
    }
    #expect(try #require(snapshot.currentFacts).resumeSourceMeasureID == nil)
}

@Test
func snapshotDuplicateProgressAndMetadataTieBreaksAreOrderIndependent() async {
    let entry = makeSnapshotEntry()
    let first = makeSnapshotProgress(songID: entry.id, revision: "a", attemptedAt: 10)
    let second = makeSnapshotProgress(songID: entry.id, revision: "b", attemptedAt: 20)
    let date = Date(timeIntervalSince1970: 100)
    let metadataA = makeSnapshotMetadata(
        songID: entry.id,
        token: entry.scoreFileVersionID,
        revision: "a",
        preparedAt: date
    )
    let metadataB = makeSnapshotMetadata(
        songID: entry.id,
        token: entry.scoreFileVersionID,
        revision: "b",
        preparedAt: date
    )
    let forward = PracticeSongHistory(
        songID: entry.id,
        progresses: [first, second],
        scoreMetadata: [metadataA, metadataB]
    )
    let reversed = PracticeSongHistory(
        songID: entry.id,
        progresses: [second, first],
        scoreMetadata: [metadataB, metadataA]
    )

    #expect(await snapshotBuilder.build(entry: entry, history: forward)
        == snapshotBuilder.build(entry: entry, history: reversed))
}

@Test
func snapshotSourceIdentityOrderDoesNotUseCollidingStrings() async throws {
    let entry = makeSnapshotEntry()
    let attemptedAt = Date(timeIntervalSince1970: 10)
    let sourceA = PracticeSourceMeasureID(
        partID: "P|1",
        sourceMeasureIndex: 2,
        sourceNumberToken: nil
    )
    let sourceB = PracticeSourceMeasureID(
        partID: "P",
        sourceMeasureIndex: 1,
        sourceNumberToken: "2|"
    )
    let sourceNil = PracticeSourceMeasureID(
        partID: "Z",
        sourceMeasureIndex: 0,
        sourceNumberToken: nil
    )
    let sourceEmpty = PracticeSourceMeasureID(
        partID: "Z",
        sourceMeasureIndex: 0,
        sourceNumberToken: ""
    )
    let facts = [
        MeasurePracticeFacts(
            sourceMeasureID: sourceA,
            handMode: .right,
            state: .learning,
            lastAttemptAt: attemptedAt
        ),
        MeasurePracticeFacts(
            sourceMeasureID: sourceA,
            handMode: .left,
            state: .learning,
            failedAttempts: 1,
            recentIssue: .wrongNote,
            lastAttemptAt: attemptedAt
        ),
        MeasurePracticeFacts(
            sourceMeasureID: sourceB,
            handMode: .left,
            state: .learning,
            failedAttempts: 1,
            recentIssue: .missedNote,
            lastAttemptAt: attemptedAt
        ),
        MeasurePracticeFacts(
            sourceMeasureID: sourceNil,
            handMode: .left,
            state: .learning,
            failedAttempts: 1,
            recentIssue: .wrongNote,
            lastAttemptAt: attemptedAt
        ),
        MeasurePracticeFacts(
            sourceMeasureID: sourceEmpty,
            handMode: .left,
            state: .learning,
            failedAttempts: 1,
            recentIssue: .missedNote,
            lastAttemptAt: attemptedAt
        ),
    ]
    let metadata = makeSnapshotMetadata(
        songID: entry.id,
        token: entry.scoreFileVersionID,
        revision: "r1"
    )

    func build(_ measureFacts: [MeasurePracticeFacts]) async throws -> SongPracticeCurrentFacts {
        let progress = SongPracticeProgress(
            identity: PracticeSongIdentity(songID: entry.id, scoreRevision: "r1"),
            measureFacts: measureFacts,
            updatedAt: attemptedAt
        )
        guard case let .current(snapshot) = await snapshotBuilder.build(
            entry: entry,
            history: PracticeSongHistory(
                songID: entry.id,
                progresses: [progress],
                scoreMetadata: [metadata]
            )
        ) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return try #require(snapshot.currentFacts)
    }

    let forward = try await build(facts)
    let reversed = try await build(Array(facts.reversed()))

    #expect(forward == reversed)
    #expect(forward.handMode == .left)
    #expect(forward.recentIssues.map(\.sourceMeasureID) == [
        sourceB,
        sourceA,
        sourceNil,
        sourceEmpty,
    ])
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

private func makeSnapshotMetadata(
    songID: UUID,
    token: UUID?,
    revision: String,
    total: Int = 10,
    preparedAt: Date = Date(timeIntervalSince1970: 100)
) -> SongScorePracticeMetadata {
    SongScorePracticeMetadata(
        songID: songID,
        scoreFileVersionID: token,
        scoreRevision: revision,
        totalSourceMeasureCount: total,
        preparedAt: preparedAt
    )
}

private func makeSnapshotProgress(
    songID: UUID,
    revision: String,
    attemptedAt: TimeInterval
) -> SongPracticeProgress {
    SongPracticeProgress(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: revision),
        measureFacts: [snapshotFact(
            0,
            hand: .both,
            state: .learning,
            attemptedAt: attemptedAt
        )],
        updatedAt: Date(timeIntervalSince1970: attemptedAt)
    )
}

private func snapshotFact(
    _ index: Int,
    hand: PracticeHandMode,
    state: MeasureLearningState,
    tempo: Double? = nil,
    issue: PracticeIssueKind? = nil,
    attemptedAt: TimeInterval
) -> MeasurePracticeFacts {
    MeasurePracticeFacts(
        sourceMeasureID: snapshotSource(index),
        handMode: hand,
        state: state,
        successfulAttempts: state == .stable ? 3 : 0,
        failedAttempts: issue == nil ? 0 : 1,
        highestStableTempoScale: tempo,
        recentIssue: issue,
        lastAttemptAt: Date(timeIntervalSince1970: attemptedAt)
    )
}

private func snapshotSource(_ index: Int) -> PracticeSourceMeasureID {
    PracticeSourceMeasureID(
        partID: "P1",
        sourceMeasureIndex: index,
        sourceNumberToken: "\(index + 1)"
    )
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
