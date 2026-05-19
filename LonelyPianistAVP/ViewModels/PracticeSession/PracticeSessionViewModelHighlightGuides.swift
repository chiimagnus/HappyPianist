import Foundation

extension PracticeSessionViewModel {
    func setCurrentHighlightGuideForStepIndex(_ stepIndex: Int) {
        highlightGuideController?.setCurrentHighlightGuideForStepIndex(stepIndex)
    }

    func updateHighlightGuideAfterStepAdvance(previousTick: Int, nextStepIndex: Int) {
        highlightGuideController?.updateHighlightGuideAfterStepAdvance(
            previousTick: previousTick,
            nextStepIndex: nextStepIndex
        )
    }

    func strictTriggerGuideIndex(forStepIndex stepIndex: Int) -> Int? {
        stateStore.strictTriggerGuideIndex(forStepIndex: stepIndex)
    }
}

