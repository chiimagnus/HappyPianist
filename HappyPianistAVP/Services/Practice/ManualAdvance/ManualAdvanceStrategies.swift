struct ManualAdvanceContext {
    let currentStepIndex: Int
    let steps: [PracticeStep]
    let measureSpans: [MusicXMLMeasureSpan]
    let activeRange: PracticeActiveRange?
}

struct ManualReplayPlan: Equatable {
    let stepRange: Range<Int>
}

protocol ManualAdvanceStrategyProtocol {
    func nextStepIndex(in context: ManualAdvanceContext) -> Int?
    func replayPlan(in context: ManualAdvanceContext) -> ManualReplayPlan?
}

struct StepManualAdvanceStrategy: ManualAdvanceStrategyProtocol {
    func nextStepIndex(in context: ManualAdvanceContext) -> Int? {
        guard context.steps.isEmpty == false else { return nil }
        let nextIndex = context.currentStepIndex + 1
        let upperBound = context.activeRange?.stepRange.upperBound ?? context.steps.count
        return nextIndex < upperBound ? nextIndex : nil
    }

    func replayPlan(in context: ManualAdvanceContext) -> ManualReplayPlan? {
        guard context.steps.indices.contains(context.currentStepIndex),
              context.activeRange?.contains(stepIndex: context.currentStepIndex) ?? true
        else {
            return nil
        }
        return ManualReplayPlan(stepRange: context.currentStepIndex ..< (context.currentStepIndex + 1))
    }
}

struct MeasureManualAdvanceStrategy: ManualAdvanceStrategyProtocol {
    func nextStepIndex(in context: ManualAdvanceContext) -> Int? {
        guard context.steps.indices.contains(context.currentStepIndex) else { return nil }
        guard let currentMeasureIndex = currentMeasureIndex(in: context) else {
            return StepManualAdvanceStrategy().nextStepIndex(in: context)
        }
        let nextMeasureIndex = currentMeasureIndex + 1
        guard context.measureSpans.indices.contains(nextMeasureIndex) else { return nil }
        let nextMeasureStartTick = context.measureSpans[nextMeasureIndex].startTick
        let nextIndex = context.steps.firstIndex { $0.tick >= nextMeasureStartTick }
        guard let nextIndex, context.activeRange?.contains(stepIndex: nextIndex) ?? true else { return nil }
        return nextIndex
    }

    func replayPlan(in context: ManualAdvanceContext) -> ManualReplayPlan? {
        guard context.steps.indices.contains(context.currentStepIndex) else { return nil }
        guard let currentMeasureIndex = currentMeasureIndex(in: context) else {
            return StepManualAdvanceStrategy().replayPlan(in: context)
        }
        let span = context.measureSpans[currentMeasureIndex]
        let indices = context.steps.indices.filter { index in
            let tick = context.steps[index].tick
            return tick >= span.startTick && tick < span.endTick &&
                (context.activeRange?.contains(stepIndex: index) ?? true)
        }
        guard let lowerBound = indices.first, let upperBoundIndex = indices.last else { return nil }
        return ManualReplayPlan(stepRange: lowerBound ..< (upperBoundIndex + 1))
    }

    private func currentMeasureIndex(in context: ManualAdvanceContext) -> Int? {
        let tick = context.steps[context.currentStepIndex].tick
        return context.measureSpans.firstIndex { tick >= $0.startTick && tick < $0.endTick }
    }
}
