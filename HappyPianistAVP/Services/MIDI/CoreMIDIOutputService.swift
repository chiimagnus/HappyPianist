import CoreMIDI
import Foundation
import os

protocol MIDIOutputSendingProtocol: AnyObject, Sendable {
    func start() throws
    func stop()
    func listDestinations() -> [MIDIDestinationInfo]

    func sendMIDI1Bytes(_ bytes: [UInt8], destinationUniqueID: Int32) throws
    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8, destinationUniqueID: Int32) throws
    func sendNoteOff(note: UInt8, channel: UInt8, destinationUniqueID: Int32) throws
    func sendControlChange(controller: UInt8, value: UInt8, channel: UInt8, destinationUniqueID: Int32) throws
    func sendProgramChange(program: UInt8, channel: UInt8, destinationUniqueID: Int32) throws
    func sendAllNotesOff(channel: UInt8, destinationUniqueID: Int32) throws
    func sendAllSoundOff(channel: UInt8, destinationUniqueID: Int32) throws
}

struct MIDIDestinationInfo: Identifiable, Equatable {
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

final class CoreMIDIOutputService: MIDIOutputSendingProtocol {
    var onDestinationListChange: (@Sendable ([MIDIDestinationInfo]) -> Void)? {
        get { stateLock.withLock { $0.onDestinationListChange } }
        set { stateLock.withLock { $0.onDestinationListChange = newValue } }
    }

    var onLastErrorMessageChange: (@Sendable (String?) -> Void)? {
        get { stateLock.withLock { $0.onLastErrorMessageChange } }
        set { stateLock.withLock { $0.onLastErrorMessageChange = newValue } }
    }

    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let refreshScheduler = DebouncedActionScheduler(debounce: .milliseconds(200))
    private let stateLock = OSAllocatedUnfairLock(initialState: OutputState())

    init(diagnosticsReporter: (any DiagnosticsReporting)? = nil) {
        self.diagnosticsReporter = diagnosticsReporter
    }

    func start() throws {
        try ensureClientAndPort()
        refreshDestinations()
    }

    func stop() {
        refreshScheduler.cancel()
        let callbacks = stateLock.withLock { state in
            if state.outputPortRef != 0 {
                MIDIPortDispose(state.outputPortRef)
                state.outputPortRef = 0
            }
            if state.clientRef != 0 {
                MIDIClientDispose(state.clientRef)
                state.clientRef = 0
            }
            state.destinationCache.removeAll(keepingCapacity: false)
            return (state.onLastErrorMessageChange, state.onDestinationListChange)
        }
        callbacks.0?(nil)
        callbacks.1?([])
    }

    func listDestinations() -> [MIDIDestinationInfo] {
        refreshDestinations()
    }

    @discardableResult
    func refreshDestinations() -> [MIDIDestinationInfo] {
        var destinationCache: [Int32: MIDIEndpointRef] = [:]
        let count = MIDIGetNumberOfDestinations()
        var results: [MIDIDestinationInfo] = []
        results.reserveCapacity(max(0, count))

        for index in 0 ..< count {
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0, let uniqueID = endpointUniqueID(endpoint) else { continue }
            destinationCache[uniqueID] = endpoint
            results.append(MIDIDestinationInfo(id: uniqueID, name: endpointName(endpoint)))
        }
        results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let cacheSnapshot = destinationCache

        let callbacks = stateLock.withLock { state in
            state.destinationCache = cacheSnapshot
            return (state.onDestinationListChange, state.onLastErrorMessageChange)
        }
        callbacks.0?(results)
        callbacks.1?(nil)
        return results
    }

    func sendMIDI1Bytes(_ bytes: [UInt8], destinationUniqueID: Int32) throws {
        try ensureClientAndPort()
        let destination = try resolveDestination(destinationUniqueID)
        try sendBytes(bytes, destination: destination)
    }

    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        try sendMIDI1Bytes([0x90 | (channel & 0x0F), note, velocity], destinationUniqueID: destinationUniqueID)
    }

    func sendNoteOff(note: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        try sendMIDI1Bytes([0x80 | (channel & 0x0F), note, 0], destinationUniqueID: destinationUniqueID)
    }

    func sendControlChange(controller: UInt8, value: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        try sendMIDI1Bytes([0xB0 | (channel & 0x0F), controller, value], destinationUniqueID: destinationUniqueID)
    }

    func sendProgramChange(program: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        try sendMIDI1Bytes([0xC0 | (channel & 0x0F), program], destinationUniqueID: destinationUniqueID)
    }

    func sendAllNotesOff(channel: UInt8, destinationUniqueID: Int32) throws {
        try sendControlChange(controller: 123, value: 0, channel: channel, destinationUniqueID: destinationUniqueID)
    }

    func sendAllSoundOff(channel: UInt8, destinationUniqueID: Int32) throws {
        try sendControlChange(controller: 120, value: 0, channel: channel, destinationUniqueID: destinationUniqueID)
    }

    private func ensureClientAndPort() throws {
        try stateLock.withLock { state in
            if state.clientRef == 0 {
                var clientRef: MIDIClientRef = 0
                let status = MIDIClientCreateWithBlock(
                    "HappyPianistAVPOutputClient" as CFString,
                    &clientRef
                ) { [weak self] _ in
                    self?.scheduleRefreshDestinations()
                }
                guard status == noErr else {
                    throw CoreMIDIOutputServiceError.clientCreate(status)
                }
                state.clientRef = clientRef
            }

            if state.outputPortRef == 0 {
                var outputPortRef: MIDIPortRef = 0
                let status = MIDIOutputPortCreate(
                    state.clientRef,
                    "HappyPianistAVPOutputPort" as CFString,
                    &outputPortRef
                )
                guard status == noErr else {
                    throw CoreMIDIOutputServiceError.outputPortCreate(status)
                }
                state.outputPortRef = outputPortRef
            }
        }
    }

    private func scheduleRefreshDestinations() {
        refreshScheduler.schedule { [weak self] in
            _ = self?.refreshDestinations()
        }
    }

    private func resolveDestination(_ destinationUniqueID: Int32) throws -> MIDIEndpointRef {
        if let endpoint = stateLock.withLock({ $0.destinationCache[destinationUniqueID] }), endpoint != 0 {
            return endpoint
        }

        _ = refreshDestinations()
        if let endpoint = stateLock.withLock({ $0.destinationCache[destinationUniqueID] }), endpoint != 0 {
            return endpoint
        }
        throw CoreMIDIOutputServiceError.destinationNotFound(destinationUniqueID)
    }

    private func sendBytes(_ bytes: [UInt8], destination: MIDIEndpointRef) throws {
        let result: (OSStatus, (@Sendable (String?) -> Void)?) = stateLock.withLock { state in
            guard state.outputPortRef != 0 else {
                return (-1, state.onLastErrorMessageChange)
            }
            return (
                Self.sendBytes(bytes, outputPortRef: state.outputPortRef, destination: destination),
                state.onLastErrorMessageChange
            )
        }
        guard result.0 == noErr else {
            diagnosticsReporter?.recordSystem(
                severity: .error,
                category: .midi,
                stage: "coreMIDI.send",
                summary: "发送 MIDI 消息失败",
                reason: "status=\(result.0)"
            )
            result.1?("MIDISend failed: \(result.0)")
            throw CoreMIDIOutputServiceError.send(result.0)
        }
    }

    private static func sendBytes(
        _ bytes: [UInt8],
        outputPortRef: MIDIPortRef,
        destination: MIDIEndpointRef
    ) -> OSStatus {
        let bufferSize = 1024
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<MIDIPacketList>.alignment
        )
        defer { buffer.deallocate() }

        let packetListPointer = buffer.assumingMemoryBound(to: MIDIPacketList.self)
        packetListPointer.initialize(to: MIDIPacketList())
        var packet = MIDIPacketListInit(packetListPointer)
        bytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            packet = MIDIPacketListAdd(
                packetListPointer,
                bufferSize,
                packet,
                0,
                bytes.count,
                baseAddress
            )
        }

        return MIDISend(outputPortRef, destination, packetListPointer)
    }

    private func endpointName(_ endpoint: MIDIEndpointRef) -> String {
        MIDIEndpointPropertyReader.stringProperty(endpoint, kMIDIPropertyDisplayName) ??
            MIDIEndpointPropertyReader.stringProperty(endpoint, kMIDIPropertyName) ??
            "Unknown MIDI Destination"
    }

    private func endpointUniqueID(_ endpoint: MIDIEndpointRef) -> Int32? {
        MIDIEndpointPropertyReader.int32Property(endpoint, kMIDIPropertyUniqueID)
    }
}

private struct OutputState {
    var clientRef: MIDIClientRef = 0
    var outputPortRef: MIDIPortRef = 0
    var destinationCache: [Int32: MIDIEndpointRef] = [:]
    var onDestinationListChange: (@Sendable ([MIDIDestinationInfo]) -> Void)?
    var onLastErrorMessageChange: (@Sendable (String?) -> Void)?
}
