import AVFAudio
import Foundation
import Practice

@MainActor
public protocol SongAudioPlayerProtocol: AnyObject {
    var onPlaybackFinished: ((UUID?) -> Void)? { get set }
    var currentEntryID: UUID? { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }

    func play(entryID: UUID, url: URL) throws
    func pause()
    func stop()
    func seek(to time: TimeInterval)
    func isPlaying(entryID: UUID) -> Bool
}

public enum SongAudioPlayerStateError: Error {
    case cannotCreatePlayer
}

@MainActor
public final class SongAudioPlayer: NSObject, SongAudioPlayerProtocol, AVAudioPlayerDelegate {
    public var onPlaybackFinished: ((UUID?) -> Void)?
    public private(set) var currentEntryID: UUID?
    public var currentTime: TimeInterval {
        audioPlayer?.currentTime ?? 0
    }

    public var duration: TimeInterval {
        audioPlayer?.duration ?? 0
    }

    private let userDefaults: UserDefaults
    private var audioPlayer: AVAudioPlayer?
    private var currentAudioOutputVolume: Float?

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        super.init()

        applyAudioOutputVolumeIfNeeded()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self, name: UserDefaults.didChangeNotification, object: nil
        )
    }

    public func play(entryID: UUID, url: URL) throws {
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

        applyAudioOutputVolumeIfNeeded()
        audioPlayer.play()
    }

    public func pause() {
        audioPlayer?.pause()
    }

    public func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        audioPlayer = nil
        currentEntryID = nil
    }

    public func seek(to time: TimeInterval) {
        guard let audioPlayer else { return }
        audioPlayer.currentTime = min(max(time, 0), audioPlayer.duration)
    }

    public func isPlaying(entryID: UUID) -> Bool {
        currentEntryID == entryID && (audioPlayer?.isPlaying ?? false)
    }

    public func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        let finishedEntryID = currentEntryID
        audioPlayer = nil
        currentEntryID = nil
        onPlaybackFinished?(finishedEntryID)
    }

    private func applyAudioOutputVolumeIfNeeded() {
        let volume = AudioOutputVolumeSettings.readAudioOutputVolume(from: userDefaults)
        let playerVolume = audioPlayer?.volume
        guard currentAudioOutputVolume != volume || playerVolume != volume else { return }
        currentAudioOutputVolume = volume
        audioPlayer?.volume = volume
    }

    @objc private func handleUserDefaultsDidChange() {
        applyAudioOutputVolumeIfNeeded()
    }
}

@MainActor
public final class SongAudioPlaybackStateController {
    private let player: SongAudioPlayerProtocol
    public private(set) var currentEntryID: UUID?
    public var onStateChanged: ((UUID?) -> Void)?

    public init(player: SongAudioPlayerProtocol) {
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

    public func toggle(entryID: UUID, url: URL) throws {
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

    public func stop() {
        player.stop()
        currentEntryID = nil
        onStateChanged?(currentEntryID)
    }

    public var currentTime: TimeInterval {
        player.currentTime
    }

    public var duration: TimeInterval {
        player.duration
    }

    public func seek(toProgress progress: Double) {
        guard duration > 0 else { return }
        player.seek(to: min(max(progress, 0), 1) * duration)
        onStateChanged?(currentEntryID)
    }

    public func isPlaying(entryID: UUID) -> Bool {
        currentEntryID == entryID && player.isPlaying(entryID: entryID)
    }
}
