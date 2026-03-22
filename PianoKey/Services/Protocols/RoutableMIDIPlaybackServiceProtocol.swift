import Foundation

struct MIDIPlaybackOutputOption: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case builtInSampler
        case midiDestination(uniqueID: Int32)
    }

    let id: String
    let title: String
    let kind: Kind

    static let builtInSamplerID = "sampler"

    static func destinationID(uniqueID: Int32) -> String {
        "destination:\(uniqueID)"
    }
}

@MainActor
protocol RoutableMIDIPlaybackServiceProtocol: MIDIPlaybackServiceProtocol {
    var availableOutputs: [MIDIPlaybackOutputOption] { get }
    var selectedOutputID: String { get set }

    func refreshAvailableOutputs()
}
