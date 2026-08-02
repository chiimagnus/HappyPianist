import Foundation


public enum MusicXMLScoreOrder: String, Codable, Equatable {
    case written
    case performed
}

public struct MusicXMLOrderSelection: Codable, Equatable {
    public let requested: MusicXMLScoreOrder
    public let applied: MusicXMLScoreOrder
    public let approximationReason: String?

    public init(
        requested: MusicXMLScoreOrder,
        applied: MusicXMLScoreOrder,
        approximationReason: String? = nil
    ) {
        self.requested = requested
        self.applied = applied
        self.approximationReason = approximationReason
    }

    public var diagnosticValue: String {
        if let approximationReason {
            return "requested=\(requested.rawValue),applied=\(applied.rawValue),approximation=\(approximationReason)"
        }
        return "requested=\(requested.rawValue),applied=\(applied.rawValue)"
    }
}

public struct MusicXMLStructureExpansionResult: Equatable {
    public let score: MusicXMLScore
    public let approximationReason: String?
}

public struct MusicXMLPerformedNoteID: Codable, Equatable, Hashable, CustomStringConvertible {
    public let sourceID: MusicXMLSourceNoteID
    public let occurrenceIndex: Int

    public var description: String {
        "\(sourceID.description)@\(occurrenceIndex)"
    }
}

public struct MusicXMLPerformedDirectionID: Codable, Equatable, Hashable, CustomStringConvertible {
    public let sourceID: MusicXMLDirectionSourceID
    public let occurrenceIndex: Int

    public var description: String {
        "\(sourceID.description)@\(occurrenceIndex)"
    }
}
