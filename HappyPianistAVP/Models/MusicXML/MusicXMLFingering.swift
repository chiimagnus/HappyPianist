import Foundation

struct MusicXMLFingeringSourceID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    let sourceNoteID: MusicXMLSourceNoteID
    let sourceOrdinal: Int

    var description: String {
        "\(sourceNoteID.description):fingering:\(max(0, sourceOrdinal))"
    }
}

enum MusicXMLFingeringOption: Codable, Equatable, Hashable, Sendable {
    case unspecified
    case enabled
    case disabled
    case unsupported(sourceToken: String)

    init(sourceToken: String?) {
        let token = sourceToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        self = switch token {
        case "": .unspecified
        case "yes": .enabled
        case "no": .disabled
        default: .unsupported(sourceToken: token)
        }
    }
}

enum MusicXMLFingeringHand: Codable, Equatable, Hashable, Sendable {
    case unspecified
    case left
    case right
    case unsupported(sourceToken: String)

    init(sourceToken: String?) {
        let token = sourceToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        self = switch token {
        case "": .unspecified
        case "left", "l", "lh": .left
        case "right", "r", "rh": .right
        default: .unsupported(sourceToken: token)
        }
    }
}

enum MusicXMLFingeringProvenance: String, Codable, Equatable, Hashable, Sendable {
    case score
    case teacher
    case user
}

struct MusicXMLFingering: Codable, Equatable, Hashable, Sendable {
    let sourceID: MusicXMLFingeringSourceID?
    let text: String
    let substitution: MusicXMLFingeringOption
    let alternate: MusicXMLFingeringOption
    let placementToken: String?
    let hand: MusicXMLFingeringHand
    let provenance: MusicXMLFingeringProvenance

    init(
        sourceID: MusicXMLFingeringSourceID? = nil,
        text: String,
        substitution: MusicXMLFingeringOption = .unspecified,
        alternate: MusicXMLFingeringOption = .unspecified,
        placementToken: String? = nil,
        hand: MusicXMLFingeringHand = .unspecified,
        provenance: MusicXMLFingeringProvenance
    ) {
        self.sourceID = sourceID
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.substitution = substitution
        self.alternate = alternate
        let placement = placementToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.placementToken = placement?.isEmpty == false ? placement : nil
        self.hand = hand
        self.provenance = provenance
    }
}

extension Collection where Element == MusicXMLFingering {
    var fingeringDisplayText: String? {
        let values = map(\.text).filter { $0.isEmpty == false }
        return values.isEmpty ? nil : values.joined(separator: "–")
    }
}
