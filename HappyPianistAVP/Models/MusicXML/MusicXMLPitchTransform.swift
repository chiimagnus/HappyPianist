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

struct MusicXMLOctaveShiftEvent: Equatable, Sendable, Identifiable {
    var sourceID: MusicXMLDirectionSourceID? = nil
    var id: MusicXMLDirectionSourceID? { sourceID }

    let tick: Int
    let kind: MusicXMLOctaveShiftKind
    let size: Int
    let numberToken: String?
    let scope: MusicXMLEventScope
}
