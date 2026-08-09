import Foundation
import Practice

@MainActor
final class NoopPracticeSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    func warmUp() throws {}
    func stop(resetCommands _: [PerformanceTransportCommand]) {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func pause() {}
    func resume() throws {}
    func setPlaybackRate(_ rate: Double) throws {
        guard rate.isFinite, (0.5 ... 2).contains(rate) else {
            throw PracticePlaybackRateError.invalidRate
        }
    }
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}
