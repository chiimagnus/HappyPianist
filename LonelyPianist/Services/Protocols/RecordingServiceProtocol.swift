import Foundation

protocol RecordingServiceProtocol {
    var isRecording: Bool { get }
    var startedAt: Date? { get }

    func startRecording(at date: Date)
    func append(event: MIDIEvent)
    func stopRecording(at date: Date, takeID: UUID, name: String) -> RecordingTake?
    func cancelRecording()
}
