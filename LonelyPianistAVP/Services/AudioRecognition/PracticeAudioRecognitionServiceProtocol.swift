import Foundation

protocol PracticeAudioRecognitionServiceProtocol: AnyObject {
    var events: AsyncStream<DetectedNoteEvent> { get }
    var statusUpdates: AsyncStream<PracticeAudioRecognitionStatus> { get }
    var debugSnapshots: AsyncStream<PracticeAudioRecognitionDebugSnapshot> { get }

    func start(
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressUntil: Date?
    ) async throws
    func updateExpectedNotes(_ expectedMIDINotes: [Int], wrongCandidateMIDINotes: [Int], generation: Int)
    func suppressRecognition(until date: Date, generation: Int)
    func stop()
}
