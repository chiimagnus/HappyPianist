import Foundation


public enum MusicXMLPerformanceNotationKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case slur
    case trillMark = "trill-mark"
    case mordent
    case invertedMordent = "inverted-mordent"
    case turn
    case invertedTurn = "inverted-turn"
    case tremolo
    case glissando
    case accidentalMark = "accidental-mark"
    case breathMark = "breath-mark"
    case caesura
    case other
}

public struct MusicXMLPerformanceNotationSourceID: Codable, Equatable, Hashable, CustomStringConvertible, Sendable {
    public let sourceNoteID: MusicXMLSourceNoteID
    public let sourceOrdinal: Int

    public init(sourceNoteID: MusicXMLSourceNoteID, sourceOrdinal: Int) {
        self.sourceNoteID = sourceNoteID
        self.sourceOrdinal = sourceOrdinal
    }

    public var description: String {
        "\(sourceNoteID.description):notation:\(max(0, sourceOrdinal))"
    }
}

public struct MusicXMLPerformanceNotation: Equatable, Sendable {
    public let sourceID: MusicXMLPerformanceNotationSourceID?
    public let kind: MusicXMLPerformanceNotationKind
    public let rawElementToken: String
    public let typeToken: String?
    public let numberToken: String?
    public let placementToken: String?
    public let textToken: String?
    public let attributes: [String: String]

    public var diagnosticKindToken: String {
        kind == .other ? rawElementToken : kind.rawValue
    }
}

extension MusicXMLScore {
    public var performanceNotationCountsByKind: [String: Int] {
        notes
            .flatMap(\.performanceNotations)
            .reduce(into: [String: Int]()) { counts, notation in
                counts[notation.diagnosticKindToken, default: 0] += 1
            }
    }

    public var unsupportedPerformanceNotationCountsByKind: [String: Int] {
        notes
            .flatMap(\.performanceNotations)
            .filter { $0.kind == .other }
            .reduce(into: [String: Int]()) { counts, notation in
                counts[notation.rawElementToken, default: 0] += 1
            }
    }
}
