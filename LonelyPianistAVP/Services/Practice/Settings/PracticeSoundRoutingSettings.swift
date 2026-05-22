import Foundation

enum PracticeSoundOutputRoute: String, CaseIterable, Identifiable, Sendable {
    case localSampler
    case externalMIDIDestination

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localSampler:
            "仅 AVP 发声"
        case .externalMIDIDestination:
            "仅真实钢琴发声"
        }
    }
}

struct PracticeSoundRoutingSettings: Sendable {
    let outputRoute: PracticeSoundOutputRoute
    let midiDestinationUniqueID: Int32?
    let sendLocalControlOff: Bool
}

