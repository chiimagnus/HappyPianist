import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func playbackControllerTogglesPlayAndPauseForSameEntry() throws {
    let player = FakeSongAudioPlayer()
    let controller = SongAudioPlaybackStateController(player: player)

    try controller.toggle(
        entryID: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
        url: URL(fileURLWithPath: "/tmp/a.mp3")
    )
    #expect(player.playCalls.count == 1)
    #expect(player.pauseCalls == 0)
    #expect(controller.currentEntryID == UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    #expect(try controller.isPlaying(entryID: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))))

    try controller.toggle(
        entryID: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
        url: URL(fileURLWithPath: "/tmp/a.mp3")
    )
    #expect(player.pauseCalls == 1)
    #expect(controller.currentEntryID == UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    #expect(try controller
        .isPlaying(entryID: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))) == false)

    try controller.toggle(
        entryID: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
        url: URL(fileURLWithPath: "/tmp/a.mp3")
    )
    #expect(player.playCalls.count == 2)
    #expect(controller.currentEntryID == UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    #expect(try controller.isPlaying(entryID: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))))
}

@Test
func playbackControllerStopsPreviousSongWhenSwitchingEntries() throws {
    let player = FakeSongAudioPlayer()
    let controller = SongAudioPlaybackStateController(player: player)

    let entryA = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let entryB = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))

    try controller.toggle(entryID: entryA, url: URL(fileURLWithPath: "/tmp/a.mp3"))
    try controller.toggle(entryID: entryB, url: URL(fileURLWithPath: "/tmp/b.mp3"))

    #expect(player.stopCalls == 1)
    #expect(player.playCalls.count == 2)
    #expect(controller.currentEntryID == entryB)
    #expect(controller.isPlaying(entryID: entryA) == false)
    #expect(controller.isPlaying(entryID: entryB))
}

@Test
func playbackControllerClearsStateWhenPlaybackFinishes() throws {
    let player = FakeSongAudioPlayer()
    let controller = SongAudioPlaybackStateController(player: player)

    let entryA = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    try controller.toggle(entryID: entryA, url: URL(fileURLWithPath: "/tmp/a.mp3"))

    #expect(controller.currentEntryID == entryA)
    player.simulatePlaybackFinished(entryID: entryA)

    #expect(controller.currentEntryID == nil)
}

private final class FakeSongAudioPlayer: SongAudioPlayerProtocol {
    var onPlaybackFinished: ((UUID?) -> Void)?
    private(set) var currentEntryID: UUID?

    private(set) var playCalls: [(UUID, URL)] = []
    private(set) var pauseCalls = 0
    private(set) var stopCalls = 0
    private var isCurrentlyPlaying = false

    func play(entryID: UUID, url: URL) throws {
        currentEntryID = entryID
        isCurrentlyPlaying = true
        playCalls.append((entryID, url))
    }

    func pause() {
        isCurrentlyPlaying = false
        pauseCalls += 1
    }

    func stop() {
        isCurrentlyPlaying = false
        currentEntryID = nil
        stopCalls += 1
    }

    func isPlaying(entryID: UUID) -> Bool {
        currentEntryID == entryID && isCurrentlyPlaying
    }

    func simulatePlaybackFinished(entryID: UUID) {
        currentEntryID = nil
        isCurrentlyPlaying = false
        onPlaybackFinished?(entryID)
    }
}
