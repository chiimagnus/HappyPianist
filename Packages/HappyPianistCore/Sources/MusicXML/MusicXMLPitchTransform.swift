import Foundation


public struct MusicXMLTransposeEvent: Equatable, Sendable {
    public let tick: Int
    public let diatonic: Int?
    public let chromatic: Int
    public let octaveChange: Int
    public let isDouble: Bool
    public let scope: MusicXMLEventScope
}

public enum MusicXMLOctaveShiftKind: String, Equatable, Sendable {
    case up
    case down
    case stop
    case `continue`
}

public struct MusicXMLOctaveShiftEvent: Equatable, Sendable {
    public var sourceID: MusicXMLDirectionSourceID?
    public var performedOccurrenceIndex: Int = 0
    public var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }

    public let tick: Int
    public let kind: MusicXMLOctaveShiftKind
    public let size: Int
    public let numberToken: String?
    public let scope: MusicXMLEventScope
}
