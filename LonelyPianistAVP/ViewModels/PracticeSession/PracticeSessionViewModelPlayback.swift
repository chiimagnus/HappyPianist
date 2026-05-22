import Foundation

extension PracticeSessionViewModel {
    func startAutoplayTaskIfNeeded() {
        playbackControlService?.startAutoplayTaskIfNeeded()
    }

    func stopAutoplayTask() {
        playbackControlService?.stopAutoplayTask()
    }

    func stopAutoplayAudio() {
        playbackControlService?.stopAutoplayAudio()
    }

    func smoothNotationScrollTick() -> Double? {
        playbackControlService?.smoothNotationScrollTick()
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
            tempoMap: self.tempoMap,
            practiceHandMode: self.practiceHandMode
        )
    }

    func startManualReplay(with plan: ManualReplayPlan) {
        stopVirtualPianoInput()
        manualReplayService?.startManualReplay(with: plan)
    }

    func stopManualReplayTask(restoreAudioRecognition: Bool = true) {
        manualReplayService?.stopManualReplayTask(restoreAudioRecognition: restoreAudioRecognition)
    }
}
