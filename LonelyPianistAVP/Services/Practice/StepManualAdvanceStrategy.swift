import Foundation

struct StepManualAdvanceStrategy: ManualAdvanceStrategyProtocol {
    func nextStepIndex(in context: ManualAdvanceContext) -> Int? {
        guard context.steps.isEmpty == false else { return nil }
        let nextIndex = context.currentStepIndex + 1
        return nextIndex < context.steps.count ? nextIndex : nil
    }

    func replayPlan(in context: ManualAdvanceContext) -> ManualReplayPlan? {
        guard context.steps.indices.contains(context.currentStepIndex) else { return nil }
        return ManualReplayPlan(stepRange: context.currentStepIndex ..< (context.currentStepIndex + 1))
    }
}
