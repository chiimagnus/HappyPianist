import Foundation

struct MIDIPlaybackOutputOption: Identifiable, Equatable {
    enum Kind: Equatable {
        case builtInSampler
        case midiDestination(uniqueID: Int32)
    }

    let id: String
    let title: String
    let kind: Kind

    static let builtInSamplerID = "sampler"
}

@MainActor
protocol RoutableMIDIPlaybackServiceProtocol: MIDIPlaybackServiceProtocol {
    var availableOutputs: [MIDIPlaybackOutputOption] { get }
    var selectedOutputID: String { get set }

    func refreshAvailableOutputs()
}
