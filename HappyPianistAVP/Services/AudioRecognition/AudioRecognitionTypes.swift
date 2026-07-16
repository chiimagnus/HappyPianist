import Foundation

enum PracticeAudioRecognitionStatus: Equatable {
    case idle
    case requestingPermission
    case permissionDenied
    case running
    case engineFailed(reason: String)
    case stopped
}

protocol PracticeAudioRecognitionServiceProtocol: AnyObject {
    var events: AsyncStream<DetectedNoteEvent> { get }
    var statusUpdates: AsyncStream<PracticeAudioRecognitionStatus> { get }

    func start(
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressUntil: Date?
    ) async throws
    func updateExpectedNotes(
        _ expectedMIDINotes: [Int], wrongCandidateMIDINotes: [Int], generation: Int
    )
    func suppressRecognition(until date: Date, generation: Int)
    func stop()
}

struct TemplateMatchResult: Equatable {
    let midiNote: Int
    let role: HarmonicTemplateCandidateRole
    let confidence: Double
    let tonalRatio: Double
    let dominanceOverWrong: Double
}
