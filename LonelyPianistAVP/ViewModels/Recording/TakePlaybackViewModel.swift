import Foundation
import Observation

@MainActor
@Observable
final class TakePlaybackViewModel {
    private let controller: TakePlaybackController

    var isPlaying = false
    var currentTakeID: UUID?
    var pausePositionSeconds: TimeInterval?

    init(controller: TakePlaybackController) {
        self.controller = controller
        syncFromController()
    }

    func play(take: RecordingTake) throws {
        try controller.play(take: take)
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
        syncFromController()
    }

    func seek(toSeconds seconds: TimeInterval) throws {
        try controller.seek(toSeconds: seconds)
        syncFromController()
    }

    func currentSeconds() -> TimeInterval {
        controller.currentSeconds()
    }

    func setPausePositionSeconds(_ seconds: TimeInterval?) {
        controller.pausePositionSeconds = seconds
        syncFromController()
    }

    private func syncFromController() {
        isPlaying = controller.isPlaying
        currentTakeID = controller.currentTakeID
        pausePositionSeconds = controller.pausePositionSeconds
    }
}
