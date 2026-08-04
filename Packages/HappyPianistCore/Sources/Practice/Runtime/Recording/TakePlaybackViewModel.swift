import Foundation
import Observation

@MainActor
@Observable
public final class TakePlaybackViewModel {
    private var controller: TakePlaybackController?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    public enum PlaybackError: LocalizedError {
        case emptyTake
        case outputUnavailable

        public var errorDescription: String? {
            switch self {
            case .emptyTake: "该录制为空，无法播放。"
            case .outputUnavailable: "请选择可用的 MIDI 输出后再播放录制。"
            }
        }
    }

    public var isPlaying = false
    public var currentTakeID: UUID?
    public var pausePositionSeconds: TimeInterval?
    public var currentPositionSeconds: TimeInterval = 0
    public var currentDurationSeconds: TimeInterval = 0
    public var scrubPositionSeconds: TimeInterval = 0
    public var isScrubbing = false
    public var canPlayback: Bool { controller != nil }

    public init(controller: TakePlaybackController? = nil) {
        self.controller = controller
    }

    deinit { progressTask?.cancel() }

    public var displayedPositionSeconds: TimeInterval {
        isScrubbing ? scrubPositionSeconds : currentPositionSeconds
    }

    public func replaceController(_ controller: TakePlaybackController?) async {
        await self.controller?.stop()
        self.controller = controller
        resetPresentation()
    }

    public func play(take: RecordingTake) async throws {
        let controller = try requireController()
        try await controller.play(take: take)
        currentDurationSeconds = take.durationSeconds
        isScrubbing = false
        await syncFromController()
    }

    public func pause() async {
        guard let controller else { return }
        await controller.pause()
        await syncFromController()
    }

    public func resume() async throws {
        let controller = try requireController()
        try await controller.resume()
        await syncFromController()
    }

    public func stop() async {
        await controller?.stop()
        resetPresentation()
    }

    public func seek(toSeconds seconds: TimeInterval) async throws {
        let controller = try requireController()
        try await controller.seek(toSeconds: seconds)
        await syncFromController()
    }

    public func currentSeconds() async -> TimeInterval {
        await syncFromController()
        return currentPositionSeconds
    }

    public func isPlaying(takeID: UUID) -> Bool { currentTakeID == takeID && isPlaying }

    public func playOrPause(take: RecordingTake) async throws {
        guard take.events.isEmpty == false else { throw PlaybackError.emptyTake }
        if currentTakeID == take.id {
            if isPlaying { await pause() } else { try await resume() }
        } else {
            try await play(take: take)
        }
    }

    public func toggleCurrentPlayback() async throws {
        if isPlaying { await pause() } else { try await resume() }
    }

    public func setPausePositionSeconds(_ seconds: TimeInterval?) {
        controller?.pausePositionSeconds = seconds
        pausePositionSeconds = seconds
        currentPositionSeconds = seconds ?? 0
    }

    public func beginScrubbing() {
        guard currentTakeID != nil else { return }
        isScrubbing = true
        scrubPositionSeconds = currentPositionSeconds
    }

    public func commitScrubbing() async throws {
        let target = max(0, min(scrubPositionSeconds, max(0, currentDurationSeconds)))
        isScrubbing = false
        if isPlaying { try await seek(toSeconds: target) } else { setPausePositionSeconds(target) }
        await syncFromController()
    }

    public func startProgressUpdates() {
        guard progressTask == nil else { return }
        progressTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                await self?.syncFromController()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    public func stopProgressUpdates() {
        progressTask?.cancel()
        progressTask = nil
    }

    private func requireController() throws -> TakePlaybackController {
        guard let controller else { throw PlaybackError.outputUnavailable }
        return controller
    }

    private func resetPresentation() {
        isPlaying = false
        currentTakeID = nil
        pausePositionSeconds = nil
        currentPositionSeconds = 0
        currentDurationSeconds = 0
        scrubPositionSeconds = 0
        isScrubbing = false
    }

    private func syncFromController() async {
        guard let controller else {
            resetPresentation()
            return
        }
        let position = await controller.currentSeconds()
        isPlaying = controller.isPlaying
        currentTakeID = controller.currentTakeID
        pausePositionSeconds = controller.pausePositionSeconds
        currentPositionSeconds = position
        if currentTakeID == nil {
            currentDurationSeconds = 0
            scrubPositionSeconds = 0
            isScrubbing = false
        } else if isScrubbing == false {
            scrubPositionSeconds = currentPositionSeconds
        }
    }
}
