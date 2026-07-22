import Foundation

struct TakeLibraryPresentationViewModel {
    func metadataText(
        for take: RecordingTake,
        alignment: RecordedTakeAlignmentDiagnostics? = nil
    ) -> String {
        let base = "\(formattedDuration(take.durationSeconds)) · \(formattedDate(take.createdAt))"
        guard let alignment else { return base }
        var facts = ["对齐 \(alignment.alignedCount)"]
        if alignment.missingCount > 0 { facts.append("漏 \(alignment.missingCount)") }
        if alignment.extraCount > 0 { facts.append("多 \(alignment.extraCount)") }
        if alignment.ambiguousCount > 0 { facts.append("歧义 \(alignment.ambiguousCount)") }
        if alignment.unknownCount > 0 { facts.append("未知 \(alignment.unknownCount)") }
        facts.append("评价 \(alignment.assessableDimensionCount)")
        if alignment.incorrectDimensionCount > 0 {
            facts.append("待改进 \(alignment.incorrectDimensionCount)")
        }
        if alignment.insufficientDimensionCount > 0 {
            facts.append("证据不足 \(alignment.insufficientDimensionCount)")
        }
        return "\(base) · \(facts.joined(separator: " · "))"
    }

    func formattedDuration(_ seconds: TimeInterval) -> String {
        let clampedSeconds = max(0, seconds)
        let minutes = Int(clampedSeconds) / 60
        let seconds = Int(clampedSeconds) % 60
        let secondsText = seconds.formatted(.number.precision(.integerLength(2)))
        return "\(minutes):\(secondsText)"
    }

    func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
