import Foundation
import Observation

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
        syncFromController()
    }

    deinit {
        progressTask?.cancel()
    }

    var displayedPositionSeconds: TimeInterval {
        isScrubbing ? scrubPositionSeconds : currentPositionSeconds
    }

    func play(take: RecordingTake) throws {
        try controller.play(take: take)
        currentDurationSeconds = take.durationSeconds
        isScrubbing = false
        syncFromController()
    }

    func pause() {
        controller.pause()
        syncFromController()
    }

    func resume() throws {
        try controller.resume()
        syncFromController()
    }

    func stop() {
        controller.stop()
        isScrubbing = false
        syncFromController()
        currentDurationSeconds = 0
    }

    func seek(toSeconds seconds: TimeInterval) throws {
        try controller.seek(toSeconds: seconds)
        syncFromController()
    }

    func currentSeconds() -> TimeInterval {
        syncFromController()
        return currentPositionSeconds
    }

    func isPlaying(takeID: UUID) -> Bool {
        currentTakeID == takeID && isPlaying
    }

    func playOrPause(take: RecordingTake) throws {
        guard take.events.isEmpty == false else { throw PlaybackError.emptyTake }

        if currentTakeID == take.id {
            if isPlaying {
                pause()
            } else {
                try resume()
            }
        } else {
            try play(take: take)
        }
    }

    func toggleCurrentPlayback() throws {
        if isPlaying {
            pause()
        } else {
            try resume()
        }
    }

    func setPausePositionSeconds(_ seconds: TimeInterval?) {
        controller.pausePositionSeconds = seconds
        syncFromController()
    }

    func beginScrubbing() {
        guard currentTakeID != nil else { return }
        isScrubbing = true
        scrubPositionSeconds = currentPositionSeconds
    }

    func commitScrubbing() throws {
        let target = max(0, min(scrubPositionSeconds, max(0, currentDurationSeconds)))
        isScrubbing = false
        if isPlaying {
            try seek(toSeconds: target)
        } else {
            setPausePositionSeconds(target)
        }
        syncFromController()
    }

    func startProgressUpdates() {
        guard progressTask == nil else { return }
        progressTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                self?.syncFromController()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopProgressUpdates() {
        progressTask?.cancel()
        progressTask = nil
    }

    private func syncFromController() {
        isPlaying = controller.isPlaying
        currentTakeID = controller.currentTakeID
        pausePositionSeconds = controller.pausePositionSeconds
        currentPositionSeconds = controller.currentSeconds()

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
