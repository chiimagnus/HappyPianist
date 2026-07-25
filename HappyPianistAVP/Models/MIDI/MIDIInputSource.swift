struct MIDIInputSource: Equatable, Hashable {
    enum Identifier: Equatable, Hashable {
        case endpointUniqueID(Int32)
        case sourceIndex(Int)
    }

    let identifier: Identifier
    let endpointName: String?
}
