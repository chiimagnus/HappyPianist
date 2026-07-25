import CoreMIDI
@testable import HappyPianistAVP
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

@Test
func coreMIDIOutputPacketListPreservesOrderedMessagesAndHostTimes() {
    let messages = [
        TimestampedMIDI1Message(hostTime: 10000, bytes: [0x90, 60, 100]),
        TimestampedMIDI1Message(hostTime: 10000, bytes: [0xB0, 64, 96]),
        TimestampedMIDI1Message(hostTime: 20000, bytes: [0x80, 60, 0]),
    ]

    let packets = CoreMIDIOutputService.withPacketList(messages) { packetList in
        packetMessages(in: packetList)
    }

    #expect(packets.flatMap(\.bytes) == messages.flatMap(\.bytes))
    #expect(
        packets.flatMap { packet in
            Array(repeating: packet.hostTime, count: packet.bytes.count)
        } == messages.flatMap { message in
            Array(repeating: message.hostTime, count: message.bytes.count)
        }
    )
    #expect(packets.allSatisfy { $0.hostTime != 0 })
}

@Test
func coreMIDIOutputRejectsOutOfOrderHostTimesBeforeSending() {
    #expect(throws: CoreMIDIOutputServiceError.self) {
        try CoreMIDIOutputService.validate([
            TimestampedMIDI1Message(hostTime: 20000, bytes: [0x90, 60, 100]),
            TimestampedMIDI1Message(hostTime: 10000, bytes: [0x80, 60, 0]),
        ])
    }
}

@Test
func endpointRouteNotificationPolicySeparatesSourceAndDestinationChanges() {
    var destinationAdded = MIDIObjectAddRemoveNotification()
    destinationAdded.messageID = .msgObjectAdded
    destinationAdded.messageSize = UInt32(MemoryLayout<MIDIObjectAddRemoveNotification>.size)
    destinationAdded.childType = .destination

    withUnsafePointer(to: &destinationAdded) { notification in
        let baseNotification = UnsafeRawPointer(notification)
            .assumingMemoryBound(to: MIDINotification.self)
        #expect(MIDIEndpointRouteNotificationPolicy.affectsDestinations(baseNotification))
        #expect(MIDIEndpointRouteNotificationPolicy.affectsSources(baseNotification) == false)
    }

    destinationAdded.childType = .source
    withUnsafePointer(to: &destinationAdded) { notification in
        let baseNotification = UnsafeRawPointer(notification)
            .assumingMemoryBound(to: MIDINotification.self)
        #expect(MIDIEndpointRouteNotificationPolicy.affectsSources(baseNotification))
        #expect(MIDIEndpointRouteNotificationPolicy.affectsDestinations(baseNotification) == false)
    }
}

private func packetMessages(in packetList: UnsafePointer<MIDIPacketList>) -> [TimestampedMIDI1Message] {
    var messages: [TimestampedMIDI1Message] = []
    withUnsafePointer(to: packetList.pointee.packet) { firstPacket in
        var packet = firstPacket
        for _ in 0 ..< Int(packetList.pointee.numPackets) {
            let bytes = withUnsafeBytes(of: packet.pointee.data) { data in
                Array(data.prefix(Int(packet.pointee.length)))
            }
            messages.append(TimestampedMIDI1Message(hostTime: packet.pointee.timeStamp, bytes: bytes))
            packet = UnsafePointer(MIDIPacketNext(UnsafeMutablePointer(mutating: packet)))
        }
    }
    return messages
}
