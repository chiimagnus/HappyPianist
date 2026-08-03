import Foundation
import Observation
import Practice

@MainActor
@Observable
final class TakePlaybackViewModel {
    private let controller: TakePlaybackController
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    enum PlaybackError: LocalizedError {
        case emptyTake

        var errorDescription: String? {
            switch self {
            case .emptyTake:
                "该录制为空，无法播放。"
            }
        }
    }

    var isPlaying = false
    var currentTakeID: UUID?
    var pausePositionSeconds: TimeInterval?
    var currentPositionSeconds: TimeInterval = 0
    var currentDurationSeconds: TimeInterval = 0
    var scrubPositionSeconds: TimeInterval = 0
    var isScrubbing = false

    init(controller: TakePlaybackController) {
        self.controller = controller
    }

    deinit {
        progressTask?.cancel()
    }

    var displayedPositionSeconds: TimeInterval {
        isScrubbing ? scrubPositionSeconds : currentPositionSeconds
    }

    func play(take: RecordingTake) async throws {
        try await controller.play(take: take)
        currentDurationSeconds = take.durationSeconds
        isScrubbing = false
        await syncFromController()
    }

    func pause() async {
        await controller.pause()
        await syncFromController()
    }

    func resume() async throws {
        try await controller.resume()
        await syncFromController()
    }

    func stop() async {
        await controller.stop()
        isScrubbing = false
        await syncFromController()
        currentDurationSeconds = 0
    }

    func seek(toSeconds seconds: TimeInterval) async throws {
        try await controller.seek(toSeconds: seconds)
        await syncFromController()
    }

    func currentSeconds() async -> TimeInterval {
        await syncFromController()
        return currentPositionSeconds
    }

    func isPlaying(takeID: UUID) -> Bool {
        currentTakeID == takeID && isPlaying
    }

    func playOrPause(take: RecordingTake) async throws {
        guard take.events.isEmpty == false else { throw PlaybackError.emptyTake }

        if currentTakeID == take.id {
            if isPlaying {
                await pause()
            } else {
                try await resume()
            }
        } else {
            try await play(take: take)
        }
    }

    func toggleCurrentPlayback() async throws {
        if isPlaying {
            await pause()
        } else {
            try await resume()
        }
    }

    func setPausePositionSeconds(_ seconds: TimeInterval?) {
        controller.pausePositionSeconds = seconds
        pausePositionSeconds = seconds
        currentPositionSeconds = seconds ?? 0
    }

    func beginScrubbing() {
        guard currentTakeID != nil else { return }
        isScrubbing = true
        scrubPositionSeconds = currentPositionSeconds
    }

    func commitScrubbing() async throws {
        let target = max(0, min(scrubPositionSeconds, max(0, currentDurationSeconds)))
        isScrubbing = false
        if isPlaying {
            try await seek(toSeconds: target)
        } else {
            setPausePositionSeconds(target)
        }
        await syncFromController()
    }

    func startProgressUpdates() {
        guard progressTask == nil else { return }
        progressTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                await self?.syncFromController()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopProgressUpdates() {
        progressTask?.cancel()
        progressTask = nil
    }

    private func syncFromController() async {
        let position = await controller.currentSeconds()
        isPlaying = controller.isPlaying
        currentTakeID = controller.currentTakeID
        pausePositionSeconds = controller.pausePositionSeconds
        currentPositionSeconds = position

        if currentTakeID == nil {
            currentDurationSeconds = 0
            scrubPositionSeconds = 0
            isScrubbing = false
            return
        }

        if isScrubbing == false {
            scrubPositionSeconds = currentPositionSeconds
        }
    }
}
