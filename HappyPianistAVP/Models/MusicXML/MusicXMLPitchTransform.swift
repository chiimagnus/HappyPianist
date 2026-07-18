import Foundation

struct MusicXMLTransposeEvent: Equatable, Sendable {
    let tick: Int
    let diatonic: Int?
    let chromatic: Int
    let octaveChange: Int
    let isDouble: Bool
    let scope: MusicXMLEventScope
}

enum MusicXMLOctaveShiftKind: String, Equatable, Sendable {
    case up
    case down
    case stop
    case `continue`
}

struct MusicXMLOctaveShiftEvent: Equatable, Sendable {
    var sourceID: MusicXMLDirectionSourceID? = nil
    var performedOccurrenceIndex: Int = 0
    var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }
    let tick: Int
    let kind: MusicXMLOctaveShiftKind
    let size: Int
    let numberToken: String?
    let scope: MusicXMLEventScope
}
