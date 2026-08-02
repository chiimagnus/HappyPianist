import MusicXML
public struct ManualAdvanceContext: Sendable {
    public let currentStepIndex: Int
    public let steps: [PracticeStep]
    public let measureSpans: [MusicXMLMeasureSpan]
    public let activeRange: PracticeActiveRange?

    public init(
        currentStepIndex: Int,
        steps: [PracticeStep],
        measureSpans: [MusicXMLMeasureSpan],
        activeRange: PracticeActiveRange?
    ) {
        self.currentStepIndex = currentStepIndex
        self.steps = steps
        self.measureSpans = measureSpans
        self.activeRange = activeRange
    }
}

public struct ManualReplayPlan: Equatable, Sendable {
    public let stepRange: Range<Int>

    public init(stepRange: Range<Int>) {
        self.stepRange = stepRange
    }
}

public protocol ManualAdvanceStrategyProtocol: Sendable {
    func nextStepIndex(in context: ManualAdvanceContext) -> Int?
    func replayPlan(in context: ManualAdvanceContext) -> ManualReplayPlan?
}

public struct StepManualAdvanceStrategy: ManualAdvanceStrategyProtocol {
    public init() {}

    public func nextStepIndex(in context: ManualAdvanceContext) -> Int? {
        guard context.steps.isEmpty == false else { return nil }
        let nextIndex = context.currentStepIndex + 1
        let upperBound = context.activeRange?.stepRange.upperBound ?? context.steps.count
        return nextIndex < upperBound ? nextIndex : nil
    }

    public func replayPlan(in context: ManualAdvanceContext) -> ManualReplayPlan? {
        guard context.steps.indices.contains(context.currentStepIndex),
              context.activeRange?.contains(stepIndex: context.currentStepIndex) ?? true
        else {
            return nil
        }
        return ManualReplayPlan(stepRange: context.currentStepIndex ..< (context.currentStepIndex + 1))
    }
}

public struct MeasureManualAdvanceStrategy: ManualAdvanceStrategyProtocol {
    public init() {}

    public func nextStepIndex(in context: ManualAdvanceContext) -> Int? {
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

    public func replayPlan(in context: ManualAdvanceContext) -> ManualReplayPlan? {
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
