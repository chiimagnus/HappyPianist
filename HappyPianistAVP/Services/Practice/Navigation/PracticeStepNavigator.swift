import Foundation

struct PracticeStepNavigator {
    struct Navigation: Equatable {
        let state: PracticeSessionState
        let currentStepIndex: Int
    }

    func restart(steps: [PracticeStep], activeRange: PracticeActiveRange? = nil) -> Navigation {
        guard steps.isEmpty == false else {
            return Navigation(state: .idle, currentStepIndex: 0)
        }
        let startIndex = activeRange?.firstStepIndex ?? 0
        guard steps.indices.contains(startIndex) else {
            return Navigation(state: .idle, currentStepIndex: 0)
        }
        return Navigation(state: .guiding(stepIndex: startIndex), currentStepIndex: startIndex)
    }

    func advance(
        steps: [PracticeStep],
        currentStepIndex: Int,
        activeRange: PracticeActiveRange? = nil
    ) -> Navigation {
        guard steps.isEmpty == false else {
            return Navigation(state: .idle, currentStepIndex: 0)
        }
        let completionIndex = activeRange?.completionStepIndex ?? steps.count
        let nextIndex = currentStepIndex + 1
        if nextIndex < completionIndex, steps.indices.contains(nextIndex) {
            return Navigation(state: .guiding(stepIndex: nextIndex), currentStepIndex: nextIndex)
        }
        return Navigation(state: .completed, currentStepIndex: completionIndex)
    }

    func move(
        to nextStepIndex: Int,
        steps: [PracticeStep],
        activeRange: PracticeActiveRange? = nil
    ) -> Navigation {
        guard steps.indices.contains(nextStepIndex), activeRange?.contains(stepIndex: nextStepIndex) ?? true else {
            return Navigation(
                state: .completed,
                currentStepIndex: activeRange?.completionStepIndex ?? steps.count
            )
        }
        return Navigation(state: .guiding(stepIndex: nextStepIndex), currentStepIndex: nextStepIndex)
    }
}
