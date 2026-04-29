import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
@MainActor
func sequencerPlaybackServiceProtocolSupportsDependencyInjection() {
    final class FakeSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
        func warmUp() throws {}
        func stop() {}
        func load(sequence _: PracticeSequencerSequence) throws {}
        func play(fromSeconds _: TimeInterval) throws {}
        func currentSeconds() -> TimeInterval {
            0
        }

        func playOneShot(midiNotes _: [Int], durationSeconds _: TimeInterval) throws {}
    }

    func accept(_ service: PracticeSequencerPlaybackServiceProtocol) {
        _ = service
    }

    accept(FakeSequencerPlaybackService())
    #expect(true)
}
