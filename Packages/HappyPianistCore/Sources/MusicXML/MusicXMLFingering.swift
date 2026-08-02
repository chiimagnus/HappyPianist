import Foundation


public struct MusicXMLFingeringSourceID: Codable, Equatable, Hashable, CustomStringConvertible {
    public let sourceNoteID: MusicXMLSourceNoteID
    public let sourceOrdinal: Int

    public var description: String {
        "\(sourceNoteID.description):fingering:\(max(0, sourceOrdinal))"
    }
}

public enum MusicXMLFingeringOption: Codable, Equatable, Hashable {
    case unspecified
    case enabled
    case disabled
    case unsupported(sourceToken: String)

    public init(sourceToken: String?) {
        let token = sourceToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        self = switch token {
        case "": .unspecified
        case "yes": .enabled
        case "no": .disabled
        default: .unsupported(sourceToken: token)
        }
    }
}

public enum MusicXMLFingeringHand: Codable, Equatable, Hashable {
    case unspecified
    case left
    case right
    case unsupported(sourceToken: String)

    public init(sourceToken: String?) {
        let token = sourceToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        self = switch token {
        case "": .unspecified
        case "left", "l", "lh": .left
        case "right", "r", "rh": .right
        default: .unsupported(sourceToken: token)
        }
    }
}

public enum MusicXMLFingeringProvenance: String, Codable, Equatable, Hashable {
    case score
    case teacher
    case user
}

public struct MusicXMLFingering: Codable, Equatable, Hashable {
    public let sourceID: MusicXMLFingeringSourceID?
    public let text: String
    public let substitution: MusicXMLFingeringOption
    public let alternate: MusicXMLFingeringOption
    public let placementToken: String?
    public let hand: MusicXMLFingeringHand
    public let provenance: MusicXMLFingeringProvenance

    public init(
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

extension Collection<MusicXMLFingering> {
    public var fingeringDisplayText: String? {
        let values = map(\.text).filter { $0.isEmpty == false }
        return values.isEmpty ? nil : values.joined(separator: "–")
    }
}
