import Foundation

public enum MIDIInputSourceSelection: Equatable, Sendable {
    /// visionOS keeps its established behaviour: subscribe to every currently available source.
    case allCurrentSources
    case endpointUniqueID(Int32)

    public func accepts(endpointUniqueID: Int32) -> Bool {
        switch self {
        case .allCurrentSources:
            true
        case let .endpointUniqueID(selectedID):
            selectedID == endpointUniqueID
        }
    }
}

public struct MIDIInputEndpoint: Identifiable, Equatable, Sendable {
    public let id: Int32
    public let name: String

    public init(id: Int32, name: String) {
        self.id = id
        self.name = name
    }
}

public enum MIDIInputSourceAvailability: Equatable, Sendable {
    case connected(selection: MIDIInputSourceSelection, sourceCount: Int)
    case selectedEndpointUnavailable(Int32)
}
