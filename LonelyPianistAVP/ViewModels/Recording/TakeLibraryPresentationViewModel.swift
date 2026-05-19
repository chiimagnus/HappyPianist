import Foundation

struct TakeLibraryPresentationViewModel: TakeLibraryPresentationViewModelProtocol {
    func metadataText(for take: RecordingTake) -> String {
        "\(formattedDuration(take.durationSeconds)) · \(formattedDate(take.createdAt))"
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
