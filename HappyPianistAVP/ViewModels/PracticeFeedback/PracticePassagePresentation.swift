import Foundation

enum PracticePassagePresentation {
    static func title(for occurrences: [PracticeMeasureOccurrenceID]) -> String {
        guard let first = occurrences.first, let last = occurrences.last else { return "" }
        let start = measureTitle(first.sourceMeasureID)
        let end = measureTitle(last.sourceMeasureID)
        guard first != last else { return "第 \(start) 小节" }

        let crossesRepeat = zip(occurrences, occurrences.dropFirst()).contains { previous, next in
            next.sourceMeasureID.sourceMeasureIndex <= previous.sourceMeasureID.sourceMeasureIndex
        }
        return crossesRepeat
            ? "第 \(start) 小节至重复后的第 \(end) 小节"
            : "第 \(start)–\(end) 小节"
    }

    static func measureTitle(_ id: PracticeSourceMeasureID) -> String {
        id.sourceNumberToken ?? "\(id.sourceMeasureIndex + 1)"
    }
}
