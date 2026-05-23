import CoreMIDI
@testable import LonelyPianistAVP
import Testing

@Test
func endpointPolicyDefaultsToMIDI1WhenProtocolIsNil() {
    #expect(MIDIEndpointConnectionPolicy.subscribedProtocol(endpointProtocolID: nil, midi2PortAvailable: true) == ._1_0)
}

@Test
func endpointPolicyUsesMIDI1WhenEndpointReportsMIDI1() {
    #expect(MIDIEndpointConnectionPolicy.subscribedProtocol(endpointProtocolID: ._1_0, midi2PortAvailable: true) == ._1_0)
}

@Test
func endpointPolicyFallsBackToMIDI1WhenMIDI2PortUnavailable() {
    #expect(MIDIEndpointConnectionPolicy.subscribedProtocol(endpointProtocolID: ._2_0, midi2PortAvailable: false) == ._1_0)
}

@Test
func endpointPolicyUsesMIDI2WhenEndpointReportsMIDI2AndPortAvailable() {
    #expect(MIDIEndpointConnectionPolicy.subscribedProtocol(endpointProtocolID: ._2_0, midi2PortAvailable: true) == ._2_0)
}
