import AVFAudio
import Foundation

protocol SongAudioPlayerProtocol: AnyObject {
    var onPlaybackFinished: ((UUID?) -> Void)? { get set }
    var currentEntryID: UUID? { get }

    func play(entryID: UUID, url: URL) throws
    func pause()
    func stop()
    func isPlaying(entryID: UUID) -> Bool
}

enum SongAudioPlayerStateError: Error {
    case cannotCreatePlayer
}

final class SongAudioPlayer: NSObject, SongAudioPlayerProtocol, AVAudioPlayerDelegate {
    var onPlaybackFinished: ((UUID?) -> Void)?
    private(set) var currentEntryID: UUID?

    private var audioPlayer: AVAudioPlayer?

    func play(entryID: UUID, url: URL) throws {
        if currentEntryID != entryID {
            stop()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            currentEntryID = entryID
        } else if audioPlayer == nil {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            currentEntryID = entryID
        }

        guard let audioPlayer else {
            throw SongAudioPlayerStateError.cannotCreatePlayer
        }

        audioPlayer.play()
    }

    func pause() {
        audioPlayer?.pause()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        audioPlayer = nil
        currentEntryID = nil
    }

    func isPlaying(entryID: UUID) -> Bool {
        currentEntryID == entryID && (audioPlayer?.isPlaying ?? false)
    }

    func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        let finishedEntryID = currentEntryID
        audioPlayer = nil
        currentEntryID = nil
        onPlaybackFinished?(finishedEntryID)
    }
}

final class SongAudioPlaybackStateController {
    private let player: SongAudioPlayerProtocol
    private(set) var currentEntryID: UUID?
    var onStateChanged: ((UUID?) -> Void)?

    init(player: SongAudioPlayerProtocol) {
        self.player = player
        currentEntryID = nil
        self.player.onPlaybackFinished = { [weak self] finishedEntryID in
            guard let self else { return }
            if currentEntryID == finishedEntryID {
                currentEntryID = nil
                onStateChanged?(nil)
            }
        }
    }

    func toggle(entryID: UUID, url: URL) throws {
        if currentEntryID == entryID {
            if player.isPlaying(entryID: entryID) {
                player.pause()
                onStateChanged?(currentEntryID)
            } else {
                try player.play(entryID: entryID, url: url)
                onStateChanged?(currentEntryID)
            }
            return
        }

        if currentEntryID != nil {
            player.stop()
            currentEntryID = nil
        }
        try player.play(entryID: entryID, url: url)
        currentEntryID = entryID
        onStateChanged?(currentEntryID)
    }

    func stop() {
        player.stop()
        currentEntryID = nil
        onStateChanged?(currentEntryID)
    }

    func isPlaying(entryID: UUID) -> Bool {
        currentEntryID == entryID && player.isPlaying(entryID: entryID)
    }
}
