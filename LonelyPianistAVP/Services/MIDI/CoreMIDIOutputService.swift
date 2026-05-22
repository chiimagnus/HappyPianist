import CoreMIDI
import Foundation
import OSLog
import os

struct MIDIDestinationInfo: Identifiable, Equatable, Sendable {
    let id: Int32
    let name: String
}

enum CoreMIDIOutputServiceError: LocalizedError {
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

final class CoreMIDIOutputService: @unchecked Sendable {
    var onDestinationListChange: (@Sendable ([MIDIDestinationInfo]) -> Void)?
    var onLastErrorMessageChange: (@Sendable (String?) -> Void)?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP", category: "CoreMIDI-AVP-Output")
    private let refreshScheduler = DebouncedActionScheduler(debounce: .milliseconds(200))

    private var clientRef: MIDIClientRef = 0
    private var outputPortRef: MIDIPortRef = 0
    private let stateLock = OSAllocatedUnfairLock(initialState: OutputState())

    func start() throws {
        try createClientIfNeeded()
        try createOutputPortIfNeeded()
        refreshDestinations()
    }

    func stop() {
        refreshScheduler.cancel()

        stateLock.withLock { state in
            state.destinationCache.removeAll(keepingCapacity: false)
        }

        if outputPortRef != 0 {
            MIDIPortDispose(outputPortRef)
            outputPortRef = 0
        }

        if clientRef != 0 {
            MIDIClientDispose(clientRef)
            clientRef = 0
        }

        onLastErrorMessageChange?(nil)
        onDestinationListChange?([])
    }

    func listDestinations() -> [MIDIDestinationInfo] {
        let results = refreshDestinations()
        return results
    }

    @discardableResult
    func refreshDestinations() -> [MIDIDestinationInfo] {
        var newDestinationCache: [Int32: MIDIEndpointRef] = [:]

        let count = MIDIGetNumberOfDestinations()
        var results: [MIDIDestinationInfo] = []
        results.reserveCapacity(max(0, count))

        for index in 0 ..< count {
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { continue }

            guard let uniqueID = endpointUniqueID(endpoint) else { continue }
            let name = endpointName(endpoint)
            newDestinationCache[uniqueID] = endpoint
            results.append(MIDIDestinationInfo(id: uniqueID, name: name))
        }

        results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let destinationCache = newDestinationCache
        stateLock.withLock { state in
            state.destinationCache = destinationCache
        }

        onDestinationListChange?(results)
        onLastErrorMessageChange?(nil)
        return results
    }

    func sendMIDI1Bytes(_ bytes: [UInt8], destinationUniqueID: Int32) throws {
        try createClientIfNeeded()
        try createOutputPortIfNeeded()

        let destination = try resolveDestination(destinationUniqueID)
        try sendBytes(bytes, destination: destination)
    }

    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        let status: UInt8 = 0x90 | (channel & 0x0F)
        try sendMIDI1Bytes([status, note, velocity], destinationUniqueID: destinationUniqueID)
    }

    func sendNoteOff(note: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        let status: UInt8 = 0x80 | (channel & 0x0F)
        try sendMIDI1Bytes([status, note, 0], destinationUniqueID: destinationUniqueID)
    }

    func sendControlChange(controller: UInt8, value: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        let status: UInt8 = 0xB0 | (channel & 0x0F)
        try sendMIDI1Bytes([status, controller, value], destinationUniqueID: destinationUniqueID)
    }

    func sendProgramChange(program: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        let status: UInt8 = 0xC0 | (channel & 0x0F)
        try sendMIDI1Bytes([status, program], destinationUniqueID: destinationUniqueID)
    }

    func sendAllNotesOff(channel: UInt8, destinationUniqueID: Int32) throws {
        try sendControlChange(controller: 123, value: 0, channel: channel, destinationUniqueID: destinationUniqueID)
    }

    func sendAllSoundOff(channel: UInt8, destinationUniqueID: Int32) throws {
        try sendControlChange(controller: 120, value: 0, channel: channel, destinationUniqueID: destinationUniqueID)
    }

    private func createClientIfNeeded() throws {
        guard clientRef == 0 else { return }

        let status = MIDIClientCreateWithBlock(
            "LonelyPianistAVPOutputClient" as CFString,
            &clientRef
        ) { [weak self] message in
            guard let self else { return }
            let notification = message.pointee
            Task { @MainActor [weak self] in
                self?.handleMIDINotification(notification)
            }
        }

        guard status == noErr else {
            throw CoreMIDIOutputServiceError.clientCreate(status)
        }
    }

    private func createOutputPortIfNeeded() throws {
        guard outputPortRef == 0 else { return }
        let status = MIDIOutputPortCreate(clientRef, "LonelyPianistAVPOutputPort" as CFString, &outputPortRef)
        guard status == noErr else {
            throw CoreMIDIOutputServiceError.outputPortCreate(status)
        }
    }

    private func handleMIDINotification(_ notification: MIDINotification) {
        _ = notification
        scheduleRefreshDestinations()
    }

    private func scheduleRefreshDestinations() {
        refreshScheduler.schedule { [weak self] in
            guard let self else { return }
            _ = self.refreshDestinations()
        }
    }

    private func resolveDestination(_ destinationUniqueID: Int32) throws -> MIDIEndpointRef {
        if let endpoint = stateLock.withLock({ $0.destinationCache[destinationUniqueID] }), endpoint != 0 {
            return endpoint
        }

        let destinations = refreshDestinations()
        if destinations.contains(where: { $0.id == destinationUniqueID }),
           let endpoint = stateLock.withLock({ $0.destinationCache[destinationUniqueID] }),
           endpoint != 0
        {
            return endpoint
        }

        throw CoreMIDIOutputServiceError.destinationNotFound(destinationUniqueID)
    }

    private func sendBytes(_ bytes: [UInt8], destination: MIDIEndpointRef) throws {
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
            onLastErrorMessageChange?("MIDISend failed: \(statusSend)")
            throw CoreMIDIOutputServiceError.send(statusSend)
        }
    }

    private func endpointName(_ endpoint: MIDIEndpointRef) -> String {
        if let displayName = MIDIEndpointPropertyReader.stringProperty(endpoint, kMIDIPropertyDisplayName) {
            return displayName
        }
        if let name = MIDIEndpointPropertyReader.stringProperty(endpoint, kMIDIPropertyName) {
            return name
        }
        return "Unknown MIDI Destination"
    }

    private func endpointUniqueID(_ endpoint: MIDIEndpointRef) -> Int32? {
        MIDIEndpointPropertyReader.int32Property(endpoint, kMIDIPropertyUniqueID)
    }
}

private struct OutputState {
    var destinationCache: [Int32: MIDIEndpointRef] = [:]
}
