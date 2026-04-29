@testable import LonelyPianistAVP
import Foundation
import Testing

@Test
@MainActor
func sequencerPlaybackServiceProtocolSupportsDependencyInjection() async {
    final class FakeSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
        func warmUp() throws {}
        func stop() {}
        func load(sequence: PracticeSequencerSequence) throws {}
        func play(fromSeconds start: TimeInterval) throws {}
        func currentSeconds() -> TimeInterval { 0 }
        func playOneShot(midiNotes: [Int], durationSeconds: TimeInterval) throws {}
    }

    func accept(_ service: PracticeSequencerPlaybackServiceProtocol) {
        _ = service
    }

    accept(FakeSequencerPlaybackService())
    #expect(true)
}
