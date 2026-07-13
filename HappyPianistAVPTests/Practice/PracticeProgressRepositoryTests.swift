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

@Test
func progressRepositoryQuarantinesCorruptedFileOnNextMutation() async throws {
    let (repository, directory) = try makeRepositoryFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    try Data("not-json".utf8).write(to: paths.fileURL)

    guard case .corrupted = await repository.load() else {
        Issue.record("Expected explicit corruption result before recovery")
        return
    }
    #expect(try String(contentsOf: paths.fileURL, encoding: .utf8) == "not-json")

    let progress = makeProgress()
    try await repository.upsert(progress)
    #expect(await repository.progress(for: progress.identity) == progress)

    let quarantinedFiles = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("progress-v1.corrupt-") }
    #expect(quarantinedFiles.count == 1)
    #expect(try String(contentsOf: quarantinedFiles[0], encoding: .utf8) == "not-json")
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
