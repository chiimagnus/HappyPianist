import Foundation

public enum PerformanceTransportCommand: Equatable, Sendable {
    case noteOff(eventID: ScorePerformanceNoteEventID)
    case controlChange(controller: UInt8, value: UInt8)
    case allNotesOff
    case allSoundOff
}
