import Foundation

struct MIDIDestinationInfo: Identifiable, Equatable, Sendable {
    let id: Int32
    let name: String
}

@MainActor
protocol MIDIOutputServiceProtocol: AnyObject {
    func listDestinations() -> [MIDIDestinationInfo]
    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8, destinationID: Int32) throws
    func sendNoteOff(note: UInt8, channel: UInt8, destinationID: Int32) throws
}

