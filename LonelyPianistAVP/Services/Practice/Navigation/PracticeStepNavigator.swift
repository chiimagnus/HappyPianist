import Foundation

struct PracticeStepNavigator {
    struct Navigation: Equatable {
        let state: PracticeSessionState
        let currentStepIndex: Int
    }

    func restart(steps: [PracticeStep]) -> Navigation {
        guard steps.isEmpty == false else {
            return Navigation(state: .idle, currentStepIndex: 0)
        }
        return Navigation(state: .guiding(stepIndex: 0), currentStepIndex: 0)
    }

    func advance(steps: [PracticeStep], currentStepIndex: Int) -> Navigation {
        guard steps.isEmpty == false else {
            return Navigation(state: .idle, currentStepIndex: 0)
        }
        if currentStepIndex + 1 < steps.count {
            let nextIndex = currentStepIndex + 1
            return Navigation(state: .guiding(stepIndex: nextIndex), currentStepIndex: nextIndex)
        }
        return Navigation(state: .completed, currentStepIndex: steps.count)
    }

    func move(to nextStepIndex: Int, steps: [PracticeStep]) -> Navigation {
        guard steps.indices.contains(nextStepIndex) else {
            return Navigation(state: .completed, currentStepIndex: steps.count)
        }
        return Navigation(state: .guiding(stepIndex: nextStepIndex), currentStepIndex: nextStepIndex)
    }
}
