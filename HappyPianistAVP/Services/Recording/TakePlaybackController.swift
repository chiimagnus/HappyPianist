import Foundation
import Practice

@MainActor
final class TakePlaybackController {
    private let playbackService: PracticeSequencerPlaybackServiceProtocol
    private let adapter: RecordingTakeSequenceAdapter

    private(set) var isPlaying = false
    private(set) var currentTakeID: UUID?
    private var cachedSequence: PracticeSequencerSequence?
    private var cachedTakeID: UUID?
    private var transportGeneration = 0
    var pausePositionSeconds: TimeInterval?

    init(
        playbackService: PracticeSequencerPlaybackServiceProtocol,
        adapter: RecordingTakeSequenceAdapter = RecordingTakeSequenceAdapter()
    ) {
        self.playbackService = playbackService
        self.adapter = adapter
    }

    func play(take: RecordingTake) async throws {
        transportGeneration &+= 1
        let generation = transportGeneration
        let sequence = try cachedSequence(for: take)
        await playbackService.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
        guard generation == transportGeneration else { return }
        try await playbackService.load(sequence: sequence)
        guard generation == transportGeneration else { return }
        try await playbackService.play(fromSeconds: 0)
        guard generation == transportGeneration else { return }
        isPlaying = true
        currentTakeID = take.id
        pausePositionSeconds = nil
    }

    func pause() async {
        guard isPlaying else { return }
        transportGeneration &+= 1
        let generation = transportGeneration
        let position = await playbackService.currentSeconds()
        guard generation == transportGeneration else { return }
        pausePositionSeconds = position
        await playbackService.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
        guard generation == transportGeneration else { return }
        isPlaying = false
    }

    func resume() async throws {
        guard let position = pausePositionSeconds else { return }
        transportGeneration &+= 1
        let generation = transportGeneration
        try await playbackService.play(fromSeconds: position)
        guard generation == transportGeneration else { return }
        isPlaying = true
        pausePositionSeconds = nil
    }

    func stop() async {
        transportGeneration &+= 1
        isPlaying = false
        currentTakeID = nil
        pausePositionSeconds = nil
        await playbackService.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
    }

    func seek(toSeconds seconds: TimeInterval) async throws {
        guard let takeID = currentTakeID, let sequence = cachedSequence, cachedTakeID == takeID
        else { return }
        transportGeneration &+= 1
        let generation = transportGeneration
        await playbackService.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
        guard generation == transportGeneration else { return }
        try await playbackService.load(sequence: sequence)
        guard generation == transportGeneration else { return }
        try await playbackService.play(fromSeconds: max(0, seconds))
        guard generation == transportGeneration else { return }
        isPlaying = true
        pausePositionSeconds = nil
    }

    func currentSeconds() async -> TimeInterval {
        guard isPlaying else { return pausePositionSeconds ?? 0 }
        let generation = transportGeneration
        let position = await playbackService.currentSeconds()
        guard generation == transportGeneration, isPlaying else { return pausePositionSeconds ?? 0 }
        return position
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
