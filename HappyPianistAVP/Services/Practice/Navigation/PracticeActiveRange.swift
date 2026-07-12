import Foundation

struct PracticeActiveRange: Equatable, Sendable {
    let passage: PracticePassage
    let occurrenceRange: Range<Int>
    let stepRange: Range<Int>
    let tickRange: Range<Int>
    let measureSpans: [MusicXMLMeasureSpan]

    var firstStepIndex: Int { stepRange.lowerBound }
    var completionStepIndex: Int { stepRange.upperBound }
    var sourceMeasureIDs: Set<PracticeSourceMeasureID> {
        Set(measureSpans.map(\.occurrenceID.sourceMeasureID))
    }

    func contains(stepIndex: Int) -> Bool {
        stepRange.contains(stepIndex)
    }

    func contains(tick: Int) -> Bool {
        tickRange.contains(tick)
    }

    func clampedStepRange(_ candidate: Range<Int>) -> Range<Int>? {
        let lower = max(candidate.lowerBound, stepRange.lowerBound)
        let upper = min(candidate.upperBound, stepRange.upperBound)
        return lower < upper ? lower ..< upper : nil
    }
}
