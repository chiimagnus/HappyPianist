import Foundation

struct ManualAdvanceContext {
    let currentStepIndex: Int
    let steps: [PracticeStep]
    let measureSpans: [MusicXMLMeasureSpan]
}

struct ManualReplayPlan: Equatable {
    let stepRange: Range<Int>
}

protocol ManualAdvanceStrategyProtocol {
    func nextStepIndex(in context: ManualAdvanceContext) -> Int?
    func replayPlan(in context: ManualAdvanceContext) -> ManualReplayPlan?
}
