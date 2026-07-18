import Foundation

extension PracticeSessionViewModel {
    func startAutoplayTaskIfNeeded() {
        playbackControlService?.startAutoplayTaskIfNeeded()
    }

    func stopAutoplayTask() {
        playbackControlService?.stopAutoplayTask()
    }

    func smoothNotationScrollTick() -> Double? {
        playbackControlService?.smoothNotationScrollTick()
    }

    func rebuildAutoplayTimeline() {
        guard
            self.stateStore.isActiveRangeInvalid == false,
            let performancePlan = self.performancePlan
        else {
            self.autoplayTimeline = .empty
            return
        }

        self.autoplayTimeline = AutoplayPerformanceTimeline.build(
            plan: performancePlan,
            guideProjection: self.highlightGuides,
            stepProjection: self.steps,
            tempoMap: self.tempoMap,
            practiceHandMode: self.practiceHandMode,
            activeRange: self.activeRange
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
