import Foundation
@testable import HappyPianistAVP
import Testing

private func makeRepositoryFixture() throws -> (FilePracticeProgressRepository, URL) {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (
        FilePracticeProgressRepository(paths: PracticeProgressPaths(rootDirectoryURL: directory)),
        directory
    )
}

private func makeProgress(songID: UUID = UUID(), revision: String = "r1") -> SongPracticeProgress {
    SongPracticeProgress(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: revision),
        updatedAt: Date(timeIntervalSince1970: 100)
    )
}

private func makeSession(
    id: UUID = UUID(),
    songID: UUID = UUID(),
    revision: String = "r1",
    persistedAt: Date = Date(timeIntervalSince1970: 200),
    windowDuration: Int64 = 5000,
    activeDuration: Int64 = 3000,
    termination: PracticeSessionTermination = .open
) throws -> PracticeSessionRecord {
    let day = try #require(PracticeLocalDay(
        year: 2026,
        month: 7,
        day: 15,
        timeZoneIdentifier: "Asia/Singapore"
    ))
    return try #require(PracticeSessionRecord(
        id: id,
        songID: songID,
        scoreRevision: revision,
        windowOpenedAt: Date(timeIntervalSince1970: 100),
        practiceStartedAt: Date(timeIntervalSince1970: 120),
        practiceDay: day,
        endedAt: termination == .open ? nil : persistedAt,
        lastPersistedAt: persistedAt,
        practiceWindowDurationMilliseconds: windowDuration,
        activePracticeDurationMilliseconds: activeDuration,
        termination: termination
    ))
}

@Test
func progressRepositoryReturnsEmptyOnFirstRunAndRoundTrips() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(await repository.load() == .loaded(PracticeProgressDocument()))
    let progress = makeProgress()
    try await repository.upsert(progress)
    #expect(await repository.progress(for: progress.identity) == progress)
}

@Test
func progressRepositoryPersistsOnlyMeasureAssessmentSummaries() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    let progress = makeProgress()
    let sourceMeasureID = PracticeSourceMeasureID(
        partID: "P1",
        sourceMeasureIndex: 0,
        sourceNumberToken: "1"
    )
    let occurrenceID = PracticeMeasureOccurrenceID(
        sourceMeasureID: sourceMeasureID,
        occurrenceIndex: 0
    )
    let passage = try #require(PracticePassage(start: occurrenceID, end: occurrenceID))
    let configuration = PracticeRoundConfiguration(
        passage: passage,
        handMode: .right,
        tempoScale: 1,
        loopEnabled: false,
        requiredSuccesses: 1
    )
    let observationID = UUID()
    let dimension = PerformanceAssessmentDimensionResult(
        dimension: .exactPitch,
        outcome: .incorrect,
        evidenceStatus: .observed,
        measurement: PerformanceAssessmentMeasurement(value: 0.75, unit: .ratio),
        sampleCount: 4,
        confidence: 0.8,
        evidence: [.unmatchedObservation(observationID: observationID)]
    )
    let assessment = PassagePerformanceAssessment(
        planID: .init(rawValue: "must-not-persist"),
        sourceGeneration: 42,
        tickRange: 0 ..< 480,
        rubricVersion: .capabilityAware,
        dimensions: [dimension],
        measures: [.init(
            occurrenceID: occurrenceID,
            tickRange: 0 ..< 480,
            dimensions: [dimension]
        )]
    )
    let reducer = PracticeAttemptReducer()
    let completion = reducer.reducePassageCompletion(
        progress: progress,
        reductionState: .init(),
        identity: progress.identity,
        configuration: configuration,
        timestamp: Date(timeIntervalSince1970: 200)
    )
    let reduced = reducer.reducePerformanceAssessment(
        progress: completion.progress,
        identity: progress.identity,
        configuration: configuration,
        timestamp: Date(timeIntervalSince1970: 200),
        assessment: assessment
    )

    try await repository.upsert(reduced)

    let data = try Data(contentsOf: paths.fileURL)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(root["schemaVersion"] as? Int == PracticeProgressDocument.currentSchemaVersion)
    let songs = try #require(root["songs"] as? [[String: Any]])
    let facts = try #require(songs.first?["measureFacts"] as? [[String: Any]])
    let maturity = try #require(facts.first?["performanceMaturity"] as? [String: Any])
    let metrics = try #require(maturity["metricSummaries"] as? [[String: Any]])
    #expect(Set(metrics[0].keys) == [
        "dimension", "outcome", "evidenceStatus", "measurement", "sampleCount", "confidence",
    ])
    #expect(metrics[0]["sampleCount"] as? Int == 4)
    #expect(metrics[0]["confidence"] as? Double == 0.8)
    #expect(allJSONKeys(in: root).isDisjoint(with: [
        "alignment", "coachingAction", "coachingDecision", "cue", "evidence", "feedback",
        "observationID", "planID", "sourceGeneration", "summary", "targetProfile",
        "teacherPrompt", "tickRange", "toleranceProfile", "visuals",
    ]))
    #expect(String(decoding: data, as: UTF8.self).contains(observationID.uuidString) == false)
    #expect(await repository.progress(for: progress.identity) == reduced)
}

@Test
func progressRepositoryDropsInjectedDerivedCoachingStateOnRewrite() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    let progress = makeProgress()
    try await repository.upsert(progress)

    let storedData = try Data(contentsOf: paths.fileURL)
    var root = try #require(JSONSerialization.jsonObject(with: storedData) as? [String: Any])
    var songs = try #require(root["songs"] as? [[String: Any]])
    songs[0]["coachingDecision"] = ["kind": "pitchAccuracy"]
    songs[0]["feedback"] = ["summary": "must-not-restore"]
    songs[0]["targetProfile"] = ["provenance": "teacher"]
    root["cue"] = ["kind": "handHighlight"]
    root["summary"] = "must-not-restore"
    try JSONSerialization.data(withJSONObject: root).write(to: paths.fileURL, options: .atomic)

    guard case let .loaded(document) = await repository.load() else {
        Issue.record("Expected derived fields to be ignored by the persistence whitelist")
        return
    }
    let restored = try #require(document.songs.first)
    #expect(restored == progress)
    try await repository.upsert(restored)

    let rewrittenData = try Data(contentsOf: paths.fileURL)
    let rewritten = try JSONSerialization.jsonObject(with: rewrittenData)
    #expect(allJSONKeys(in: rewritten).isDisjoint(with: [
        "coachingAction", "coachingDecision", "cue", "feedback", "summary", "targetProfile",
        "toleranceProfile",
    ]))
}

@Test
func progressRepositoryUpgradesVersionlessProgressWithoutLosingFacts() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    let songID = UUID()
    let legacyJSON = """
    {
      "songs": [{
        "identity": {
          "songID": "\(songID.uuidString)",
          "scoreRevision": "legacy"
        },
        "measureFacts": [{
          "sourceMeasureID": {
            "partID": "P1",
            "sourceMeasureIndex": 0,
            "sourceNumberToken": "1"
          },
          "handMode": "right",
          "state": "stable",
          "successfulAttempts": 3,
          "failedAttempts": 1,
          "consecutiveSuccesses": 2,
          "highestStableTempoScale": 0.75,
          "recentIssue": "wrongNote",
          "lastAttemptAt": "1970-01-01T00:01:40Z"
        }],
        "updatedAt": "1970-01-01T00:01:40Z"
      }],
      "scoreMetadata": [],
      "sessions": []
    }
    """
    try Data(legacyJSON.utf8).write(to: paths.fileURL)

    guard case let .loaded(document) = await repository.load() else {
        Issue.record("Expected versionless progress to migrate")
        return
    }
    let progress = try #require(document.songs.first)
    let facts = try #require(progress.measureFacts.first)
    #expect(document.schemaVersion == PracticeProgressDocument.currentSchemaVersion)
    #expect(facts.state == .pitchStepStable)
    #expect(facts.successfulAttempts == 3)
    #expect(facts.failedAttempts == 1)
    #expect(facts.consecutiveSuccesses == 2)
    #expect(facts.highestPitchStepStableTempoScale == 0.75)
    #expect(facts.recentIssue == .wrongNote)
    #expect(facts.performanceMaturity == nil)

    try await repository.upsert(progress)
    let upgradedData = try Data(contentsOf: paths.fileURL)
    let upgraded = try #require(JSONSerialization.jsonObject(with: upgradedData) as? [String: Any])
    #expect(upgraded["schemaVersion"] as? Int == PracticeProgressDocument.currentSchemaVersion)
    #expect(await repository.progress(for: progress.identity) == progress)
}

@Test
func progressRepositoryRejectsUnknownFutureSchema() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    let json = #"{"schemaVersion":3,"songs":[],"scoreMetadata":[],"sessions":[]}"#
    try Data(json.utf8).write(to: paths.fileURL)

    guard case .corrupted = await repository.load() else {
        Issue.record("Expected an unknown schema version to fail closed")
        return
    }
}

@Test(arguments: [Data("not-json".utf8), Data(), Data(" \n\t".utf8)])
func progressRepositoryPreservesCorruptedFileAndRejectsEveryMutation(
    corruptedData: Data
) async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    try corruptedData.write(to: paths.fileURL)

    guard case .corrupted = await repository.load() else {
        Issue.record("Expected explicit corruption result before recovery")
        return
    }
    #expect(try Data(contentsOf: paths.fileURL) == corruptedData)

    let progress = makeProgress()
    let metadata = makeMetadata(songID: progress.identity.songID)
    await #expect(throws: PracticeProgressRepositoryError.self) {
        try await repository.upsert(progress)
    }
    await #expect(throws: PracticeProgressRepositoryError.self) {
        try await repository.upsert(metadata)
    }
    await #expect(throws: PracticeProgressRepositoryError.self) {
        try await repository.remove(songID: progress.identity.songID)
    }
    guard case .corrupted = await repository.history(for: progress.identity.songID) else {
        Issue.record("Expected corrupted history")
        return
    }
    #expect(try Data(contentsOf: paths.fileURL) == corruptedData)
}

@Test
func progressRepositoryDistinguishesTemporaryReadFailureFromCorruption() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    try FileManager.default.createDirectory(at: paths.fileURL, withIntermediateDirectories: false)

    guard case .unavailable = await repository.load() else {
        Issue.record("Expected explicit unavailable result for a file read failure")
        return
    }
    guard case .unavailable = await repository.history(for: UUID()) else {
        Issue.record("Expected unavailable history for a file read failure")
        return
    }
    await #expect(throws: PracticeProgressRepositoryError.self) {
        try await repository.upsert(makeProgress())
    }
    #expect(FileManager.default.fileExists(atPath: paths.fileURL.path()))
}

@Test
func progressRepositoryBacksUpCorruptionBeforeInstallingEmptyStrictSchema() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    let corruptedData = Data("not-json".utf8)
    try corruptedData.write(to: paths.fileURL)

    let recovery = try await repository.recoverFromCorruption()
    let backupURL = try #require(recovery.backupURL)
    #expect(try Data(contentsOf: backupURL) == corruptedData)
    #expect(await repository.load() == .loaded(PracticeProgressDocument()))
    #expect(try await repository.recoverFromCorruption() == .notNeeded)
    #expect(try Data(contentsOf: backupURL) == corruptedData)
}

@Test
func progressRepositoryReplacementFailureLeavesCorruptedOriginalUntouched() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    let corruptedData = Data("not-json".utf8)
    try corruptedData.write(to: paths.fileURL)
    let repository = FilePracticeProgressRepository(
        paths: paths,
        replaceFile: { _, _, _, _ in
            throw CocoaError(.fileWriteUnknown)
        }
    )

    await #expect(throws: PracticeProgressRepositoryError.self) {
        try await repository.recoverFromCorruption()
    }

    #expect(try Data(contentsOf: paths.fileURL) == corruptedData)
    guard case .corrupted = await repository.load() else {
        Issue.record("Expected corruption to remain active after replacement failure")
        return
    }
    let children = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )
    #expect(children == [paths.fileURL])
}

@Test
func progressRepositorySerializesConcurrentUpsertsAndRemovesSong() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = makeProgress()
    let second = makeProgress()

    async let writeFirst: Void = repository.upsert(first)
    async let writeSecond: Void = repository.upsert(second)
    _ = try await (writeFirst, writeSecond)

    guard case let .loaded(document) = await repository.load() else {
        Issue.record("Expected loaded document")
        return
    }
    #expect(Set(document.songs.map(\.identity.songID)) == Set([first.identity.songID, second.identity.songID]))

    try await repository.remove(songID: first.identity.songID)
    #expect(await repository.progress(for: first.identity) == nil)
    #expect(await repository.progress(for: second.identity) == second)
}

@Test
func progressRepositoryUpsertsAndFinalizesOneSessionWithoutDuplicatingCheckpoints() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let id = UUID()
    let songID = UUID()
    let opened = try makeSession(id: id, songID: songID)
    let checkpoint = try makeSession(
        id: id,
        songID: songID,
        persistedAt: Date(timeIntervalSince1970: 230),
        windowDuration: 8000,
        activeDuration: 6000
    )
    let finalized = try makeSession(
        id: id,
        songID: songID,
        persistedAt: Date(timeIntervalSince1970: 240),
        windowDuration: 9000,
        activeDuration: 7000,
        termination: .normal
    )

    try await repository.upsert(opened)
    try await repository.upsert(checkpoint)
    guard case let .loaded(liveDocument) = await repository.load() else {
        Issue.record("Expected a readable live session")
        return
    }
    #expect(liveDocument.sessions == [checkpoint])

    try await repository.upsert(finalized)
    try await repository.upsert(finalized)
    guard case let .loaded(finalizedDocument) = await repository.load() else {
        Issue.record("Expected a readable finalized session")
        return
    }
    #expect(finalizedDocument.sessions == [finalized])
}

@Test
func progressRepositoryStoresSessionsInDeterministicOrder() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let songID = UUID()
    let lowID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let highID = try #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))
    let low = try makeSession(id: lowID, songID: songID)
    let high = try makeSession(id: highID, songID: songID)

    try await repository.upsert(high)
    try await repository.upsert(low)

    guard case let .loaded(document) = await repository.load() else {
        Issue.record("Expected deterministically sorted sessions")
        return
    }
    #expect(document.sessions.map(\.id) == [lowID, highID])
}

@Test
func progressRepositoryRecoversOnlySessionsNotLiveInCurrentActor() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    let stale = try makeSession(songID: UUID())
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(PracticeProgressDocument(sessions: [stale])).write(to: paths.fileURL)

    let repository = FilePracticeProgressRepository(paths: paths)
    guard case let .loaded(recoveredDocument) = await repository.load() else {
        Issue.record("Expected stale session recovery")
        return
    }
    let recovered = try #require(recoveredDocument.sessions.first)
    #expect(recovered.id == stale.id)
    #expect(recovered.endedAt == stale.lastPersistedAt)
    #expect(recovered.termination == .recoveredAfterInterruption)
    #expect(recovered.practiceWindowDurationMilliseconds == stale.practiceWindowDurationMilliseconds)
    #expect(recovered.activePracticeDurationMilliseconds == stale.activePracticeDurationMilliseconds)

    #expect(await repository.load() == .loaded(recoveredDocument))

    let live = try makeSession(songID: UUID())
    try await repository.upsert(live)
    guard case let .loaded(documentWithLiveSession) = await repository.load() else {
        Issue.record("Expected live session to stay readable")
        return
    }
    #expect(documentWithLiveSession.sessions.contains(live))
}

@Test
func interruptedSessionRecoveryWriteFailureIsUnavailableNotCorruption() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    let openSession = try makeSession()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let originalData = try encoder.encode(PracticeProgressDocument(sessions: [openSession]))
    try originalData.write(to: paths.fileURL)
    let repository = FilePracticeProgressRepository(
        paths: paths,
        writeDocument: { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    )

    guard case .unavailable = await repository.load() else {
        Issue.record("Expected a recovery write failure to remain an availability failure")
        return
    }
    #expect(try Data(contentsOf: paths.fileURL) == originalData)
}

@Test
func progressRepositoryRejectsSessionRegressionAndIdentityCollision() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = try makeSession()
    try await repository.upsert(original)

    let regressed = try makeSession(
        id: original.id,
        songID: original.songID,
        persistedAt: Date(timeIntervalSince1970: 250),
        windowDuration: 4000,
        activeDuration: 2000
    )
    await #expect(throws: PracticeSessionMutationError.durationRegression(id: original.id)) {
        try await repository.upsert(regressed)
    }

    let collision = try makeSession(id: original.id, songID: UUID())
    await #expect(throws: PracticeSessionMutationError.identityMismatch(id: original.id)) {
        try await repository.upsert(collision)
    }
}

@Test
func progressRepositoryPreservesMetadataAndProgressAcrossConcernUpsertsAndRemoval() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let songID = UUID()
    let progress = makeProgress(songID: songID)
    let metadata = makeMetadata(songID: songID)
    let session = try makeSession(songID: songID)
    let otherSession = try makeSession(songID: UUID())

    try await repository.upsert(metadata)
    try await repository.upsert(progress)
    try await repository.upsert(session)
    try await repository.upsert(otherSession)
    guard case let .loaded(history) = await repository.history(for: songID) else {
        Issue.record("Expected loaded history")
        return
    }
    #expect(history.progresses == [progress])
    #expect(history.scoreMetadata == [metadata])
    #expect(history.sessions == [session])

    try await repository.remove(songID: songID)
    #expect(await repository.history(for: songID) == .loaded(
        PracticeSongHistory(songID: songID, progresses: [], scoreMetadata: [], sessions: [])
    ))
    guard case let .loaded(otherHistory) = await repository.history(for: otherSession.songID) else {
        Issue.record("Expected another song's session to survive removal")
        return
    }
    #expect(otherHistory.sessions == [otherSession])
}

@Test
func progressRepositorySelectsDuplicateIdentityDeterministically() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    let songID = UUID()
    let older = makeProgress(songID: songID)
    let newer = SongPracticeProgress(
        identity: older.identity,
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    let document = PracticeProgressDocument(songs: [newer, older])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(document).write(to: paths.fileURL)

    #expect(await repository.progress(for: older.identity) == newer)
    guard case let .loaded(history) = await repository.history(for: songID) else {
        Issue.record("Expected loaded history")
        return
    }
    #expect(history.progresses == [newer, older])
}

@Test
func progressRepositoryDoesNotLetLateOlderMetadataRegressSameIdentity() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let songID = UUID()
    let token = UUID()
    let newer = SongScorePracticeMetadata(
        songID: songID,
        scoreFileVersionID: token,
        scoreRevision: "r1",
        totalSourceMeasureCount: 8,
        preparedAt: Date(timeIntervalSince1970: 200)
    )
    let older = SongScorePracticeMetadata(
        songID: songID,
        scoreFileVersionID: token,
        scoreRevision: "r1",
        totalSourceMeasureCount: 8,
        preparedAt: Date(timeIntervalSince1970: 100)
    )

    try await repository.upsert(newer)
    try await repository.upsert(older)

    guard case let .loaded(history) = await repository.history(for: songID) else {
        Issue.record("Expected loaded history")
        return
    }
    #expect(history.scoreMetadata == [newer])
}

private func makeMetadata(
    songID: UUID,
    token: UUID = UUID(),
    revision: String = "r1"
) -> SongScorePracticeMetadata {
    SongScorePracticeMetadata(
        songID: songID,
        scoreFileVersionID: token,
        scoreRevision: revision,
        totalSourceMeasureCount: 8,
        preparedAt: Date(timeIntervalSince1970: 100)
    )
}

private func allJSONKeys(in value: Any) -> Set<String> {
    if let object = value as? [String: Any] {
        return object.reduce(into: Set(object.keys)) { keys, entry in
            keys.formUnion(allJSONKeys(in: entry.value))
        }
    }
    if let array = value as? [Any] {
        return array.reduce(into: []) { keys, element in
            keys.formUnion(allJSONKeys(in: element))
        }
    }
    return []
}

private extension PracticeProgressRecoveryResult {
    var backupURL: URL? {
        guard case let .recovered(backupURL) = self else { return nil }
        return backupURL
    }
}
