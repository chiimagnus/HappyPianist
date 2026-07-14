import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func staleAudioURLResolutionCannotStartPlaybackAfterSelectionChanges() async throws {
    let first = makeListeningEntry(name: "first")
    let second = makeListeningEntry(name: "second")
    let fileStore = DelayedListeningFileStore()
    let player = RecordingListeningPlayer()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [first, second], lastSelectedEntryID: first.id),
        fileStore: fileStore,
        audioPlayer: player
    )

    let listenTask = Task { await viewModel.didTapListen(entryID: first.id) }
    try await waitForRequests(1, in: fileStore)
    viewModel.selectEntry(second.id)
    await listenTask.value

    #expect(player.playedEntryIDs.isEmpty)
}

@Test
@MainActor
func outOfOrderSameEntryAudioResolutionsHonorOnlyLatestIntent() async throws {
    let entry = makeListeningEntry(name: "same")
    let fileStore = DelayedListeningFileStore()
    let player = RecordingListeningPlayer()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: entry.id),
        fileStore: fileStore,
        audioPlayer: player
    )

    let first = Task { await viewModel.didTapListen(entryID: entry.id) }
    try await waitForRequests(1, in: fileStore)
    let second = Task { await viewModel.didTapListen(entryID: entry.id) }
    try await waitForRequests(2, in: fileStore)
    await second.value
    await first.value

    #expect(player.playedEntryIDs == [entry.id])
}

private func makeListeningEntry(name: String) -> SongLibraryEntry {
    SongLibraryEntry(
        id: UUID(),
        displayName: name,
        musicXMLFileName: "\(name).musicxml",
        importedAt: .distantPast,
        audioFileName: "\(name).mp3"
    )
}

private func waitForRequests(_ count: Int, in store: DelayedListeningFileStore) async throws {
    for _ in 0..<100 {
        if await store.requestCount == count { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for audio URL request")
}

private actor DelayedListeningFileStore: SongFileStoreProtocol {
    private var requests = 0
    var requestCount: Int { requests }

    func scoreFileURL(fileName _: String) async throws -> URL { throw CocoaError(.fileNoSuchFile) }
    func audioFileURL(fileName: String) async throws -> URL {
        requests += 1
        let request = requests
        try await Task.sleep(for: request == 1 ? .milliseconds(50) : .milliseconds(5))
        return URL(fileURLWithPath: "/tmp/audio.mp3")
    }
    func deleteScoreFile(named _: String) async throws {}
    func deleteAudioFile(named _: String) async throws {}
}

@MainActor
private final class RecordingListeningPlayer: SongAudioPlayerProtocol {
    var onPlaybackFinished: ((UUID?) -> Void)?
    private(set) var currentEntryID: UUID?
    private(set) var playedEntryIDs: [UUID] = []
    var currentTime: TimeInterval { 0 }
    var duration: TimeInterval { 1 }

    func play(entryID: UUID, url _: URL) throws {
        currentEntryID = entryID
        playedEntryIDs.append(entryID)
    }
    func pause() {}
    func stop() { currentEntryID = nil }
    func seek(to _: TimeInterval) {}
    func isPlaying(entryID: UUID) -> Bool { currentEntryID == entryID }
}
