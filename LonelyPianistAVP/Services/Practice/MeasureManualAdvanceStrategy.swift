import Foundation

struct MeasureManualAdvanceStrategy: ManualAdvanceStrategyProtocol {
    func nextStepIndex(in context: ManualAdvanceContext) -> Int? {
        guard context.steps.isEmpty == false else { return nil }
        guard context.steps.indices.contains(context.currentStepIndex) else { return nil }
        guard let currentMeasureIndex = currentMeasureIndex(in: context) else {
            return StepManualAdvanceStrategy().nextStepIndex(in: context)
        }
        let nextMeasureIndex = currentMeasureIndex + 1
        guard context.measureSpans.indices.contains(nextMeasureIndex) else { return nil }
        let nextMeasureStartTick = context.measureSpans[nextMeasureIndex].startTick
        return context.steps.firstIndex { $0.tick >= nextMeasureStartTick }
    }

    func replayPlan(in context: ManualAdvanceContext) -> ManualReplayPlan? {
        guard context.steps.indices.contains(context.currentStepIndex) else { return nil }
        guard let currentMeasureIndex = currentMeasureIndex(in: context) else {
            return StepManualAdvanceStrategy().replayPlan(in: context)
        }
        let span = context.measureSpans[currentMeasureIndex]
        let indices = context.steps.indices.filter { index in
            let tick = context.steps[index].tick
            return tick >= span.startTick && tick < span.endTick
        }
        guard let lowerBound = indices.first, let upperBoundIndex = indices.last else { return nil }
        return ManualReplayPlan(stepRange: lowerBound ..< (upperBoundIndex + 1))
    }

    private func currentMeasureIndex(in context: ManualAdvanceContext) -> Int? {
        guard context.steps.indices.contains(context.currentStepIndex) else { return nil }
        let tick = context.steps[context.currentStepIndex].tick
        return context.measureSpans.firstIndex { span in
            tick >= span.startTick && tick < span.endTick
        }
    }
}
