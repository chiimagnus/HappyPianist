import CoreMIDI

struct MIDIEndpointConnectionPolicy: Sendable {
    static func subscribedProtocol(endpointProtocolID: MIDIProtocolID?, midi2PortAvailable: Bool) -> MIDIProtocolID {
        guard endpointProtocolID == ._2_0, midi2PortAvailable else {
            return ._1_0
        }
        return ._2_0
    }
}

