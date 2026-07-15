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

@Test
func progressRepositoryReturnsEmptyOnFirstRunAndRoundTrips() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(await repository.load() == .loaded(PracticeProgressDocument()))
    let progress = makeProgress()
    try await repository.upsert(progress)
    #expect(await repository.progress(for: progress.identity) == progress)
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
func progressRepositoryPreservesMetadataAndProgressAcrossConcernUpsertsAndRemoval() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let songID = UUID()
    let progress = makeProgress(songID: songID)
    let metadata = makeMetadata(songID: songID)

    try await repository.upsert(metadata)
    try await repository.upsert(progress)
    guard case let .loaded(history) = await repository.history(for: songID) else {
        Issue.record("Expected loaded history")
        return
    }
    #expect(history.progresses == [progress])
    #expect(history.scoreMetadata == [metadata])

    try await repository.remove(songID: songID)
    #expect(await repository.history(for: songID) == .loaded(
        PracticeSongHistory(songID: songID, progresses: [], scoreMetadata: [])
    ))
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
    token: UUID? = nil,
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

private extension PracticeProgressRecoveryResult {
    var backupURL: URL? {
        guard case let .recovered(backupURL) = self else { return nil }
        return backupURL
    }
}
