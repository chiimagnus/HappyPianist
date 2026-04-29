import Foundation

extension PracticeSessionViewModel {
    func setCurrentHighlightGuideForStepIndex(_ stepIndex: Int) {
        guard steps.indices.contains(stepIndex) else {
            currentHighlightGuideIndex = nil
            return
        }
        currentHighlightGuideIndex = strictTriggerGuideIndex(forStepIndex: stepIndex)
    }

    func updateHighlightGuideAfterStepAdvance(previousTick: Int, nextStepIndex: Int) {
        guard autoplayState == .off else {
            setCurrentHighlightGuideForStepIndex(nextStepIndex)
            return
        }
        manualHighlightTransitionTask?.cancel()
        guard steps.indices.contains(nextStepIndex) else {
            currentHighlightGuideIndex = nil
            return
        }
        let nextTick = steps[nextStepIndex].tick
        let transitionIndex = highlightGuides.firstIndex { guide in
            guide.tick > previousTick && guide.tick < nextTick && (guide.kind == .release || guide.kind == .gap)
        }
        guard let transitionIndex else {
            setCurrentHighlightGuideForStepIndex(nextStepIndex)
            return
        }
        currentHighlightGuideIndex = transitionIndex
        manualHighlightTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await sleeper.sleep(for: .seconds(0.12))
            guard Task.isCancelled == false else { return }
            setCurrentHighlightGuideForStepIndex(nextStepIndex)
            manualHighlightTransitionTask = nil
        }
    }

    func strictTriggerGuideIndex(forStepIndex stepIndex: Int) -> Int? {
        highlightGuides.firstIndex { guide in
            guide.practiceStepIndex == stepIndex && guide.kind == .trigger
        }
    }
}
