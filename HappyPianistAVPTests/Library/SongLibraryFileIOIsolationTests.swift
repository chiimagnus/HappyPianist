import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func staleAudioURLResolutionCannotStartPlaybackAfterSelectionChanges() async {
    let first = makeListeningEntry(name: "first")
    let second = makeListeningEntry(name: "second")
    let fileStore = ControlledListeningFileStore()
    let player = RecordingListeningPlayer()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [first, second], lastSelectedEntryID: first.id),
        fileStore: fileStore,
        audioPlayer: player
    )

    let listenTask = Task { @MainActor in await viewModel.didTapListen(entryID: first.id) }
    await fileStore.waitForRequestCount(1)
    viewModel.selectEntry(second.id)
    await fileStore.succeedRequest(at: 0)
    await listenTask.value

    #expect(viewModel.selectedEntryID == second.id)
    #expect(player.playedEntryIDs.isEmpty)
}

@Test
@MainActor
func staleAudioURLFailureDoesNotPublishPlaybackErrorAfterSelectionChanges() async {
    let first = makeListeningEntry(name: "first")
    let second = makeListeningEntry(name: "second")
    let fileStore = ControlledListeningFileStore()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [first, second], lastSelectedEntryID: first.id),
        fileStore: fileStore
    )

    let listenTask = Task { @MainActor in await viewModel.didTapListen(entryID: first.id) }
    await fileStore.waitForRequestCount(1)
    viewModel.selectEntry(second.id)
    await fileStore.failRequest(at: 0)
    await listenTask.value

    #expect(viewModel.selectedEntryID == second.id)
    #expect(viewModel.errorMessage == nil)
}

@Test
@MainActor
func outOfOrderSameEntryAudioResolutionsHonorOnlyLatestIntent() async {
    let entry = makeListeningEntry(name: "same")
    let fileStore = ControlledListeningFileStore()
    let player = RecordingListeningPlayer()
    let viewModel = SongLibraryViewModelTestHarness.make(
        index: SongLibraryIndex(entries: [entry], lastSelectedEntryID: entry.id),
        fileStore: fileStore,
        audioPlayer: player
    )

    let first = Task { @MainActor in await viewModel.didTapListen(entryID: entry.id) }
    await fileStore.waitForRequestCount(1)
    let second = Task { @MainActor in await viewModel.didTapListen(entryID: entry.id) }
    await fileStore.waitForRequestCount(2)
    await fileStore.succeedRequest(at: 1)
    await second.value
    await fileStore.succeedRequest(at: 0)
    await first.value

    #expect(player.playedEntryIDs == [entry.id])
}

private func makeListeningEntry(name: String) -> SongLibraryEntry {
    SongLibraryEntry(
        id: UUID(),
        displayName: name,
        musicXMLFileName: "\(name).musicxml",
        scoreFileVersionID: UUID(),
        importedAt: .distantPast,
        audioFileName: "\(name).mp3"
    )
}

private actor ControlledListeningFileStore: SongFileStoreProtocol {
    private var requests: [CheckedContinuation<URL, Error>?] = []

    func scoreFileURL(fileName _: String) async throws -> URL {
        throw CocoaError(.fileNoSuchFile)
    }

    func audioFileURL(fileName _: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(continuation)
        }
    }

    func waitForRequestCount(_ count: Int) async {
        while requests.count < count {
            await Task.yield()
        }
    }

    func succeedRequest(at index: Int) {
        guard requests.indices.contains(index), let request = requests[index] else { return }
        requests[index] = nil
        request.resume(returning: URL(fileURLWithPath: "/tmp/audio.mp3"))
    }

    func failRequest(at index: Int) {
        guard requests.indices.contains(index), let request = requests[index] else { return }
        requests[index] = nil
        request.resume(throwing: CocoaError(.fileReadUnknown))
    }

    func deleteScoreFile(named _: String) async throws {}
    func deleteAudioFile(named _: String) async throws {}
}

@MainActor
private final class RecordingListeningPlayer: SongAudioPlayerProtocol {
    var onPlaybackFinished: ((UUID?) -> Void)?
    private(set) var currentEntryID: UUID?
    private(set) var playedEntryIDs: [UUID] = []
    var currentTime: TimeInterval {
        0
    }

    var duration: TimeInterval {
        1
    }

    func play(entryID: UUID, url _: URL) throws {
        currentEntryID = entryID
        playedEntryIDs.append(entryID)
    }

    func pause() {}
    func stop() {
        currentEntryID = nil
    }

    func seek(to _: TimeInterval) {}
    func isPlaying(entryID: UUID) -> Bool {
        currentEntryID == entryID
    }
}
