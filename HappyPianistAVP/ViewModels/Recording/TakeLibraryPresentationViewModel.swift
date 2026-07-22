import Foundation

struct TakeLibraryPresentationViewModel {
    func metadataText(
        for take: RecordingTake,
        alignment: RecordedTakeAlignmentDiagnostics? = nil
    ) -> String {
        let base = "\(formattedDuration(take.durationSeconds)) · \(formattedDate(take.createdAt))"
        guard let alignment else { return base }
        return "\(base) · 对齐 \(alignment.alignedCount)/\(alignment.observationCount)"
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
