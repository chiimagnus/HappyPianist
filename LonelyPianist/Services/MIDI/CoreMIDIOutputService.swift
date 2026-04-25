import CoreMIDI
import Foundation
import OSLog

enum MIDIOutputServiceError: LocalizedError {
    case clientCreate(OSStatus)
    case outputPortCreate(OSStatus)
    case destinationNotFound(Int32)
    case send(OSStatus)

    var errorDescription: String? {
        switch self {
            case let .clientCreate(status):
                "Failed to create MIDI client: \(status)"
            case let .outputPortCreate(status):
                "Failed to create MIDI output port: \(status)"
            case let .destinationNotFound(id):
                "MIDI destination not found: \(id)"
            case let .send(status):
                "Failed to send MIDI message: \(status)"
        }
    }
}

@MainActor
final class CoreMIDIOutputService: MIDIOutputServiceProtocol {
    private let logger = Logger(subsystem: "com.chiimagnus.LonelyPianist", category: "CoreMIDIOutput")

    private var clientRef: MIDIClientRef = 0
    private var outputPortRef: MIDIPortRef = 0
    private var destinationCache: [Int32: MIDIEndpointRef] = [:]

    init() {
        // Best-effort initialization; errors will surface on use.
        _ = try? ensureClientAndPort()
    }

    deinit {
        if outputPortRef != 0 {
            MIDIPortDispose(outputPortRef)
            outputPortRef = 0
        }
        if clientRef != 0 {
            MIDIClientDispose(clientRef)
            clientRef = 0
        }
    }

    func listDestinations() -> [MIDIDestinationInfo] {
        destinationCache.removeAll(keepingCapacity: true)

        let count = MIDIGetNumberOfDestinations()
        guard count > 0 else { return [] }

        var results: [MIDIDestinationInfo] = []
        results.reserveCapacity(count)

        for index in 0 ..< count {
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { continue }

            guard let uniqueID = endpointUniqueID(endpoint) else { continue }
            let name = endpointName(endpoint)
            destinationCache[uniqueID] = endpoint
            results.append(MIDIDestinationInfo(id: uniqueID, name: name))
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8, destinationID: Int32) throws {
        let destination = try resolveDestination(destinationID)
        let status: UInt8 = 0x90 | ((channel &- 1) & 0x0F)
        try sendBytes([status, note, velocity], destination: destination)
    }

    func sendNoteOff(note: UInt8, channel: UInt8, destinationID: Int32) throws {
        let destination = try resolveDestination(destinationID)
        let status: UInt8 = 0x80 | ((channel &- 1) & 0x0F)
        try sendBytes([status, note, 0], destination: destination)
    }

    private func ensureClientAndPort() throws {
        if clientRef == 0 {
            let status = MIDIClientCreate("LonelyPianistMIDIOutClient" as CFString, nil, nil, &clientRef)
            guard status == noErr else { throw MIDIOutputServiceError.clientCreate(status) }
        }

        if outputPortRef == 0 {
            let status = MIDIOutputPortCreate(clientRef, "LonelyPianistMIDIOutPort" as CFString, &outputPortRef)
            guard status == noErr else { throw MIDIOutputServiceError.outputPortCreate(status) }
        }
    }

    private func resolveDestination(_ destinationID: Int32) throws -> MIDIEndpointRef {
        try ensureClientAndPort()

        if let cached = destinationCache[destinationID], cached != 0 {
            return cached
        }

        // Slow-path resolve: enumerate destinations again.
        let destinations = listDestinations()
        if let match = destinations.first(where: { $0.id == destinationID }),
           let endpoint = destinationCache[match.id]
        {
            return endpoint
        }

        throw MIDIOutputServiceError.destinationNotFound(destinationID)
    }

    private func sendBytes(_ bytes: [UInt8], destination: MIDIEndpointRef) throws {
        try ensureClientAndPort()

        let bufferSize = 1024
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<MIDIPacketList>.alignment
        )
        defer { buffer.deallocate() }

        let packetListPtr = buffer.assumingMemoryBound(to: MIDIPacketList.self)
        packetListPtr.initialize(to: MIDIPacketList())

        var packet = MIDIPacketListInit(packetListPtr)
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            packet = MIDIPacketListAdd(packetListPtr, bufferSize, packet, 0, bytes.count, base)
        }

        let statusSend = MIDISend(outputPortRef, destination, packetListPtr)
        guard statusSend == noErr else {
            logger.error("MIDISend failed: \(statusSend, privacy: .public)")
            throw MIDIOutputServiceError.send(statusSend)
        }
    }

    private func endpointName(_ endpoint: MIDIEndpointRef) -> String {
        var displayName: Unmanaged<CFString>?
        let displayStatus = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &displayName)
        if displayStatus == noErr, let displayName {
            return displayName.takeUnretainedValue() as String
        }

        var name: Unmanaged<CFString>?
        let nameStatus = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
        if nameStatus == noErr, let name {
            return name.takeUnretainedValue() as String
        }

        return "Unknown MIDI Destination"
    }

    private func endpointUniqueID(_ endpoint: MIDIEndpointRef) -> Int32? {
        var uniqueID: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
        guard status == noErr else { return nil }
        return uniqueID
    }
}
