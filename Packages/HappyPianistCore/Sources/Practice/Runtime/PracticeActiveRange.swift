import Foundation
import MusicXML

public struct PracticeActiveRange: Equatable, Sendable {
    public let passage: PracticePassage
    public let occurrenceRange: Range<Int>
    public let stepRange: Range<Int>
    public let tickRange: Range<Int>
    public let measureSpans: [MusicXMLMeasureSpan]

    public var firstStepIndex: Int {
        stepRange.lowerBound
    }

    public var completionStepIndex: Int {
        stepRange.upperBound
    }

    public var sourceMeasureIDs: Set<PracticeSourceMeasureID> {
        Set(measureSpans.map(\.occurrenceID.sourceMeasureID))
    }

    public func contains(stepIndex: Int) -> Bool {
        stepRange.contains(stepIndex)
    }

    public func contains(tick: Int) -> Bool {
        tickRange.contains(tick)
    }

    public func clampedStepRange(_ candidate: Range<Int>) -> Range<Int>? {
        let lower = max(candidate.lowerBound, stepRange.lowerBound)
        let upper = min(candidate.upperBound, stepRange.upperBound)
        return lower < upper ? lower ..< upper : nil
    }
}
