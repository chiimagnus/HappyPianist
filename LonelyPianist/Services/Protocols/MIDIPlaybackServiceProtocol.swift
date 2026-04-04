import Foundation

@MainActor
protocol MIDIPlaybackServiceProtocol: AnyObject {
    var isPlaying: Bool { get }
    var onPlaybackFinished: (@Sendable () -> Void)? { get set }

    func play(take: RecordingTake) throws
    func play(take: RecordingTake, fromOffsetSec offsetSec: TimeInterval) throws
    func stop()
}
