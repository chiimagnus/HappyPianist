import Foundation

enum MusicXMLPerformanceNotationKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
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

struct MusicXMLPerformanceNotationSourceID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    let sourceNoteID: MusicXMLSourceNoteID
    let sourceOrdinal: Int

    var description: String {
        "\(sourceNoteID.description):notation:\(max(0, sourceOrdinal))"
    }
}

struct MusicXMLPerformanceNotation: Equatable, Sendable {
    let sourceID: MusicXMLPerformanceNotationSourceID?
    let kind: MusicXMLPerformanceNotationKind
    let rawElementToken: String
    let typeToken: String?
    let numberToken: String?
    let placementToken: String?
    let textToken: String?
    let attributes: [String: String]

    var diagnosticKindToken: String {
        kind == .other ? rawElementToken : kind.rawValue
    }
}

extension MusicXMLScore {
    var performanceNotationCountsByKind: [String: Int] {
        notes
            .flatMap(\.performanceNotations)
            .reduce(into: [String: Int]()) { counts, notation in
                counts[notation.diagnosticKindToken, default: 0] += 1
            }
    }

    var unsupportedPerformanceNotationCountsByKind: [String: Int] {
        notes
            .flatMap(\.performanceNotations)
            .filter { $0.kind == .other }
            .reduce(into: [String: Int]()) { counts, notation in
                counts[notation.rawElementToken, default: 0] += 1
            }
    }
}
