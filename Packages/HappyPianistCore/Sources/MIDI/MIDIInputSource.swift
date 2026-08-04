public struct MIDIInputSource: Equatable, Hashable, Sendable {
    public enum Identifier: Equatable, Hashable, Sendable {
        case endpointUniqueID(Int32)
        case unidentified
    }

    public let identifier: Identifier
    public let endpointName: String?

    public init(identifier: Identifier, endpointName: String?) {
        self.identifier = identifier
        self.endpointName = endpointName
    }
}
