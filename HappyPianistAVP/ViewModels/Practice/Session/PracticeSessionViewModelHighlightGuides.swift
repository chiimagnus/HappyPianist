import Foundation
import Practice

extension PracticeSessionViewModel {
    func currentFingeringByMIDINote(isAutoplayEnabled: Bool) -> [Int: String] {
        guard isAutoplayEnabled else { return [:] }
        return currentPianoHighlightGuide?.fingeringByMIDINote ?? [:]
    }

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
