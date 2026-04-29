import Foundation
import os

extension PracticeSessionViewModel {
    func startManualReplay(with plan: ManualReplayPlan) {
        let shouldResumeRecognitionWhenReplayEnds = isManualReplayPlaying
            ? shouldResumeAudioRecognitionAfterManualReplay
            : isAudioRecognitionRunning
        stopManualReplayTask(restoreAudioRecognition: false)
        guard plan.stepRange.isEmpty == false else { return }
        guard steps.indices.contains(plan.stepRange.lowerBound) else { return }
        do {
            try (noteOutput as? PracticeMIDINoteOutputWarmupProtocol)?.warmUp()
        } catch {
            recordPlaybackError(error)
        }

        shouldResumeAudioRecognitionAfterManualReplay = shouldResumeRecognitionWhenReplayEnds
        stopAudioRecognition()
        feedbackResetTask?.cancel()
        feedbackResetTask = nil
        feedbackState = .none
        manualReplayGeneration += 1
        let generation = manualReplayGeneration
        let startIndex = plan.stepRange.lowerBound
        isManualReplayPlaying = true
        moveToStep(startIndex, shouldPlaySound: false)

        let tempoMapSnapshot = tempoMap
        let isTimingDebugEnabled = UserDefaults.standard.bool(forKey: "practiceTimingDebugEnabled")
        let timingStartWallSeconds = timingClock.nowSeconds()
        let timingBaseTick = steps[startIndex].tick
        let timingBaseTempoSeconds = tempoMapSnapshot.timeSeconds(atTick: timingBaseTick)
        var timingLoopCount = 0
        manualReplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var completedReplay = false
            defer {
                if self.manualReplayGeneration == generation {
                    if completedReplay, self.steps.indices.contains(startIndex) {
                        self.currentStepIndex = startIndex
                        self.state = .guiding(stepIndex: startIndex)
                        self.setCurrentHighlightGuideForStepIndex(startIndex)
                    }
                    self.manualReplayTask = nil
                    self.isManualReplayPlaying = false
                    if self.shouldResumeAudioRecognitionAfterManualReplay {
                        self.refreshAudioRecognitionForCurrentState()
                    }
                    self.shouldResumeAudioRecognitionAfterManualReplay = false
                }
            }

            for index in plan.stepRange {
                guard Task.isCancelled == false else { return }
                guard self.steps.indices.contains(index) else { return }
                timingLoopCount += 1
                self.currentStepIndex = index
                self.state = .guiding(stepIndex: index)
                self.setCurrentHighlightGuideForStepIndex(index)
                self.playCurrentStepSound(applyRecognitionSuppress: false)

                let nextIndex = index + 1
                guard plan.stepRange.contains(nextIndex), self.steps.indices.contains(nextIndex) else { continue }
                let nextTick = self.steps[nextIndex].tick
                let expectedElapsed = tempoMapSnapshot.timeSeconds(atTick: nextTick) - timingBaseTempoSeconds
                let wallElapsed = timingClock.nowSeconds() - timingStartWallSeconds
                let waitSeconds = expectedElapsed - wallElapsed

                if waitSeconds >= 0.01 {
                    try? await self.sleeper.sleep(for: .seconds(waitSeconds))
                }
                if isTimingDebugEnabled {
                    let wallElapsedAfter = timingClock.nowSeconds() - timingStartWallSeconds
                    let driftSeconds = wallElapsedAfter - expectedElapsed
                    if driftSeconds > 0.05 || timingLoopCount.isMultiple(of: 50) {
                        let deltaTicks = self.steps[nextIndex].tick - self.steps[index].tick
                        timingLogger.debug(
                            "manual replay step=\(index, privacy: .public) tick=\(self.steps[index].tick, privacy: .public) Δtick=\(deltaTicks, privacy: .public) wait=\(waitSeconds, privacy: .public)s expected=\(expectedElapsed, privacy: .public)s wall=\(wallElapsedAfter, privacy: .public)s drift=\(driftSeconds, privacy: .public)s"
                        )
                    }
                }
            }
            completedReplay = true
        }
    }

    func stopManualReplayTask(restoreAudioRecognition: Bool = true) {
        manualReplayGeneration += 1
        manualReplayTask?.cancel()
        manualReplayTask = nil
        if isManualReplayPlaying {
            isManualReplayPlaying = false
            if restoreAudioRecognition, shouldResumeAudioRecognitionAfterManualReplay {
                refreshAudioRecognitionForCurrentState()
            }
        }
        shouldResumeAudioRecognitionAfterManualReplay = false
    }
}
