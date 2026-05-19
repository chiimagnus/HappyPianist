import Foundation

protocol TakeLibraryPresentationViewModelProtocol {
    func metadataText(for take: RecordingTake) -> String
    func formattedDuration(_ seconds: TimeInterval) -> String
    func formattedDate(_ date: Date) -> String
}
