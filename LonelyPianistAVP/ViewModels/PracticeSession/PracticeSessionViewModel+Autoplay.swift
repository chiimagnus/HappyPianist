import Foundation

extension PracticeSessionViewModel {
    func startAutoplayTaskIfNeeded() {
        playbackCoordinator?.startAutoplayTaskIfNeeded()
    }

    func stopAutoplayTask() {
        playbackCoordinator?.stopAutoplayTask()
    }

    func stopAutoplayAudio() {
        playbackCoordinator?.stopAutoplayAudio()
    }

    func smoothNotationScrollTick() -> Double? {
        playbackCoordinator?.smoothNotationScrollTick()
    }

    func rebuildAutoplayTimeline() {
        guard
            let pedalTimeline,
            let fermataTimeline,
            highlightGuides.isEmpty == false
        else {
            autoplayTimeline = .empty
            return
        }

        autoplayTimeline = AutoplayPerformanceTimeline.build(
            guides: highlightGuides,
            steps: steps,
            pedalTimeline: pedalTimeline,
            fermataTimeline: fermataTimeline,
            tempoMap: tempoMap
        )
    }
}

