import Foundation

@MainActor
final class TakePlaybackController {
    private let playbackService: PracticeSequencerPlaybackServiceProtocol
    private let adapter: RecordingTakeSequenceAdapter

    private(set) var isPlaying = false
    private(set) var currentTakeID: UUID?
    private var cachedSequence: PracticeSequencerSequence?
    private var cachedTakeID: UUID?
    var pausePositionSeconds: TimeInterval?

    init(
        playbackService: PracticeSequencerPlaybackServiceProtocol,
        adapter: RecordingTakeSequenceAdapter = RecordingTakeSequenceAdapter()
    ) {
        self.playbackService = playbackService
        self.adapter = adapter
    }

    func play(take: RecordingTake) throws {
        let sequence = try cachedSequence(for: take)
        try playbackService.load(sequence: sequence)
        try playbackService.play(fromSeconds: 0)
        isPlaying = true
        currentTakeID = take.id
        pausePositionSeconds = nil
    }

    func pause() {
        guard isPlaying else { return }
        pausePositionSeconds = playbackService.currentSeconds()
        playbackService.stop()
        isPlaying = false
    }

    func resume() throws {
        guard let position = pausePositionSeconds else { return }
        try playbackService.play(fromSeconds: position)
        isPlaying = true
        pausePositionSeconds = nil
    }

    func stop() {
        playbackService.stop()
        isPlaying = false
        currentTakeID = nil
        pausePositionSeconds = nil
    }

    func seek(toSeconds seconds: TimeInterval) throws {
        guard let takeID = currentTakeID, let sequence = cachedSequence, cachedTakeID == takeID
        else { return }
        playbackService.stop()
        try playbackService.load(sequence: sequence)
        try playbackService.play(fromSeconds: max(0, seconds))
        isPlaying = true
        pausePositionSeconds = nil
    }

    func currentSeconds() -> TimeInterval {
        guard isPlaying else { return pausePositionSeconds ?? 0 }
        return playbackService.currentSeconds()
    }

    private func cachedSequence(for take: RecordingTake) throws -> PracticeSequencerSequence {
        if cachedTakeID == take.id, let cachedSequence {
            return cachedSequence
        }
        let sequence = try adapter.buildSequence(from: take)
        cachedSequence = sequence
        cachedTakeID = take.id
        return sequence
    }
}
