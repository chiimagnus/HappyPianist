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
            let pedalTimeline = self.pedalTimeline,
            let fermataTimeline = self.fermataTimeline,
            self.highlightGuides.isEmpty == false
        else {
            self.autoplayTimeline = .empty
            return
        }

        self.autoplayTimeline = AutoplayPerformanceTimeline.build(
            guides: self.highlightGuides,
            steps: self.steps,
            pedalTimeline: pedalTimeline,
            fermataTimeline: fermataTimeline,
            tempoMap: self.tempoMap
        )
    }

    func startManualReplay(with plan: ManualReplayPlan) {
        stopVirtualPianoInput()
        manualReplayCoordinator?.startManualReplay(with: plan)
    }

    func stopManualReplayTask(restoreAudioRecognition: Bool = true) {
        manualReplayCoordinator?.stopManualReplayTask(restoreAudioRecognition: restoreAudioRecognition)
    }
}
