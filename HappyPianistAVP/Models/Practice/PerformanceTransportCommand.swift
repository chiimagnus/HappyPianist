import Foundation

enum PerformanceTransportCommand: Equatable {
    case noteOff(eventID: ScorePerformanceNoteEventID)
    case controlChange(controller: UInt8, value: UInt8)
    case allNotesOff
    case allSoundOff
}
