import Foundation

@MainActor
final class NoopPracticeSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    func warmUp() throws {}
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval { 0 }
    func playOneShot(noteOns _: [PracticeOneShotNoteOn], durationSeconds _: TimeInterval) throws {}
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}

