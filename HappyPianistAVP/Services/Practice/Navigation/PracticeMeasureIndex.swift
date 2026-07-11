import Foundation

enum PracticeMeasureIndexDiagnostic: Error, Equatable, Sendable {
    case noMeasures
    case passageBoundaryNotFound
    case passageOrderInvalid
    case noStepsInPassage
    case partiallyOverlappingStep(stepIndex: Int)
}

struct PracticeMeasureIndex: Equatable {
    let steps: [PracticeStep]
    let measureSpans: [MusicXMLMeasureSpan]

    init(steps: [PracticeStep], measureSpans: [MusicXMLMeasureSpan]) {
        self.steps = steps
        self.measureSpans = measureSpans.sorted { lhs, rhs in
            if lhs.startTick != rhs.startTick { return lhs.startTick < rhs.startTick }
            return lhs.occurrenceIndex < rhs.occurrenceIndex
        }
    }

    func occurrenceID(forStepIndex stepIndex: Int) -> PracticeMeasureOccurrenceID? {
        guard steps.indices.contains(stepIndex) else { return nil }
        let tick = steps[stepIndex].tick
        return measureSpans.first { tick >= $0.startTick && tick < $0.endTick }?.occurrenceID
    }

    func stepRange(forOccurrenceRange occurrenceRange: Range<Int>) throws -> Range<Int> {
        guard occurrenceRange.isEmpty == false,
              measureSpans.indices.contains(occurrenceRange.lowerBound),
              measureSpans.indices.contains(occurrenceRange.upperBound - 1)
        else {
            throw PracticeMeasureIndexDiagnostic.passageBoundaryNotFound
        }

        let startTick = measureSpans[occurrenceRange.lowerBound].startTick
        let endTick = measureSpans[occurrenceRange.upperBound - 1].endTick
        let matching = steps.indices.filter { index in
            let tick = steps[index].tick
            return tick >= startTick && tick < endTick
        }
        guard let first = matching.first, let last = matching.last else {
            throw PracticeMeasureIndexDiagnostic.noStepsInPassage
        }
        return first ..< (last + 1)
    }

    func resolve(_ passage: PracticePassage) throws -> PracticeActiveRange {
        guard measureSpans.isEmpty == false else {
            throw PracticeMeasureIndexDiagnostic.noMeasures
        }
        guard let startIndex = measureSpans.firstIndex(where: { $0.occurrenceID == passage.start }),
              let endIndex = measureSpans.firstIndex(where: { $0.occurrenceID == passage.end })
        else {
            throw PracticeMeasureIndexDiagnostic.passageBoundaryNotFound
        }
        guard startIndex <= endIndex else {
            throw PracticeMeasureIndexDiagnostic.passageOrderInvalid
        }

        let occurrenceRange = startIndex ..< (endIndex + 1)
        let stepRange = try stepRange(forOccurrenceRange: occurrenceRange)
        let spans = Array(measureSpans[occurrenceRange])
        return PracticeActiveRange(
            passage: passage,
            occurrenceRange: occurrenceRange,
            stepRange: stepRange,
            tickRange: spans[0].startTick ..< spans[spans.count - 1].endTick,
            measureSpans: spans
        )
    }
}
