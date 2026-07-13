import CoreMIDI
import Foundation
import os
import OSLog

enum BluetoothMIDIInputEventSourceServiceError: LocalizedError {
    case clientCreate(OSStatus)
    case portCreate(OSStatus)
    case sourceRefresh(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .clientCreate(status):
            "Failed to create MIDI client: \(status)"
        case let .portCreate(status):
            "Failed to create MIDI input port: \(status)"
        case let .sourceRefresh(status):
            "Failed to refresh MIDI sources: \(status)"
        }
    }
}

final class BluetoothMIDIInputEventSourceService: PracticeInputEventSourceProtocol, Sendable {
    func midi1EventsStream() -> AsyncStream<MIDI1InputEvent> {
        midi1EventsBroadcaster.makeStream()
    }

    func midi2EventsStream() -> AsyncStream<MIDI2InputEvent> {
        midi2EventsBroadcaster.makeStream()
    }

    private let lifecycleLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "HappyPianistAVP",
        category: "BluetoothMIDI"
    )
    private let refreshScheduler = DebouncedActionScheduler(debounce: .milliseconds(200))
    private let lifecycleLock = OSAllocatedUnfairLock(initialState: BluetoothMIDILifecycleState())
    private let stateLock = OSAllocatedUnfairLock(initialState: BluetoothMIDIInputEventSourceState())

    private let midi1EventsBroadcaster = AsyncStreamBroadcaster<MIDI1InputEvent>()
    private let midi2EventsBroadcaster = AsyncStreamBroadcaster<MIDI2InputEvent>()

    private let midi1Decoder = MIDI1MessageDecoder()
    private let midi2Decoder = MIDI2MessageDecoder()

    init() {}

    func start() throws {
        let shouldStart = stateLock.withLock { state in
            if state.isRunning { return false }
            state.isRunning = true
            state.lastProtocolMismatchLoggedAtUptimeSeconds = 0
            return true
        }
        guard shouldStart else { return }

        do {
            try lifecycleLock.withLock { lifecycle in
                guard stateLock.withLock({ $0.isRunning }) else { return }
                try createClientIfNeeded(state: &lifecycle)
                try createMIDI1InputPortIfNeeded(state: &lifecycle)
                try createMIDI2InputPortIfNeeded(state: &lifecycle)
                try refreshSourcesLocked(state: &lifecycle)
            }
        } catch {
            stateLock.withLock { $0.isRunning = false }
            lifecycleLock.withLock { stopLifecycleLocked(state: &$0) }
            throw error
        }
    }

    func stop() {
        stateLock.withLock { $0.isRunning = false }
        refreshScheduler.cancel()
        lifecycleLock.withLock { stopLifecycleLocked(state: &$0) }
    }

    func refreshSources() throws {
        try lifecycleLock.withLock { lifecycle in
            guard stateLock.withLock({ $0.isRunning }) else { return }
            try refreshSourcesLocked(state: &lifecycle)
        }
    }

    private func refreshSourcesLocked(state: inout BluetoothMIDILifecycleState) throws {
        guard state.midi1InputPortRef != 0 || state.midi2InputPortRef != 0 else { return }

        disconnectAllSources(state: &state)

        var failedStatus: OSStatus?
        var sourceDescriptions: [String] = []
        let sourceCount = MIDIGetNumberOfSources()

        for index in 0 ..< sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }

            let endpointName = MIDIEndpointPropertyReader.stringProperty(source, kMIDIPropertyDisplayName) ??
                MIDIEndpointPropertyReader.stringProperty(source, kMIDIPropertyName)
            let endpointUniqueID = MIDIEndpointPropertyReader.int32Property(source, kMIDIPropertyUniqueID)
            let connectionContext = EndpointConnectionContext(
                sourceIndex: index,
                endpointUniqueID: endpointUniqueID,
                endpointName: endpointName
            )
            let connRefCon = Unmanaged.passUnretained(connectionContext).toOpaque()

            let endpointProtocolID = MIDIEndpointPropertyReader.int32Property(source, kMIDIPropertyProtocolID)
                .flatMap(MIDIProtocolID.init(rawValue:))
            if endpointProtocolID == ._2_0, state.midi2InputPortRef == 0 {
                lifecycleLogger.warning("Endpoint reports MIDI 2.0 but MIDI 2.0 port is unavailable; subscribing via MIDI 1.0 port: \(self.describeEndpoint(source) ?? "unknown", privacy: .public)")
            }
            let targetProtocol = MIDIEndpointConnectionPolicy.subscribedProtocol(
                endpointProtocolID: endpointProtocolID,
                midi2PortAvailable: state.midi2InputPortRef != 0
            )
            let targetPortRef = targetProtocol == ._2_0 ? state.midi2InputPortRef : state.midi1InputPortRef

            let status = MIDIPortConnectSource(targetPortRef, source, connRefCon)
            if status == noErr {
                state.connectedSources.append(ConnectedSource(
                    portRef: targetPortRef,
                    endpoint: source,
                    connectionContext: connectionContext
                ))
                let subscribed = targetProtocol == ._2_0 ? "midi2" : "midi1"
                let description = (describeEndpoint(source) ?? "sourceIndex=\(index)") + ",subscribed=\(subscribed)"
                sourceDescriptions.append(description)
            } else {
                failedStatus = status
                lifecycleLogger.error("Failed to connect source \(index, privacy: .public): \(status, privacy: .public)")
            }
        }

        if sourceDescriptions.isEmpty == false {
            lifecycleLogger.info("Connected MIDI sources: \(sourceDescriptions.joined(separator: " | "), privacy: .public)")
        }
        if state.connectedSources.isEmpty, let failedStatus {
            throw BluetoothMIDIInputEventSourceServiceError.sourceRefresh(failedStatus)
        }
    }

    private func createClientIfNeeded(state: inout BluetoothMIDILifecycleState) throws {
        guard state.clientRef == 0 else { return }

        let status = MIDIClientCreateWithBlock(
            "HappyPianistAVPBluetoothMIDIEventsClient" as CFString,
            &state.clientRef
        ) { [weak self] message in
            self?.handleMIDINotification(message.pointee)
        }

        guard status == noErr else {
            throw BluetoothMIDIInputEventSourceServiceError.clientCreate(status)
        }
    }

    private func createMIDI1InputPortIfNeeded(state: inout BluetoothMIDILifecycleState) throws {
        guard state.midi1InputPortRef == 0 else { return }

        let status = MIDIInputPortCreateWithProtocol(
            state.clientRef,
            "HappyPianistAVPBluetoothMIDIEventsInput-MIDI1" as CFString,
            MIDIProtocolID._1_0,
            &state.midi1InputPortRef
        ) { [weak self] eventList, srcConnRefCon in
            guard let self else { return }
            self.handleEventList(eventList, srcConnRefCon: srcConnRefCon)
        }

        guard status == noErr else {
            throw BluetoothMIDIInputEventSourceServiceError.portCreate(status)
        }
    }

    private func createMIDI2InputPortIfNeeded(state: inout BluetoothMIDILifecycleState) throws {
        guard state.midi2InputPortRef == 0 else { return }

        let status = MIDIInputPortCreateWithProtocol(
            state.clientRef,
            "HappyPianistAVPBluetoothMIDIEventsInput-MIDI2" as CFString,
            MIDIProtocolID._2_0,
            &state.midi2InputPortRef
        ) { [weak self] eventList, srcConnRefCon in
            guard let self else { return }
            self.handleEventList(eventList, srcConnRefCon: srcConnRefCon)
        }

        if status != noErr {
            lifecycleLogger.warning("Failed to create MIDI 2.0 input port, falling back to MIDI 1.0 only: \(status, privacy: .public)")
            state.midi2InputPortRef = 0
        }
    }

    private func handleMIDINotification(_ notification: MIDINotification) {
        _ = notification
        scheduleRefreshSources()
    }

    private func scheduleRefreshSources() {
        guard stateLock.withLock({ $0.isRunning }) else { return }
        refreshScheduler.schedule { [weak self] in
            guard let self, self.stateLock.withLock({ $0.isRunning }) else { return }
            do {
                try self.refreshSources()
            } catch {
                self.lifecycleLogger.error("Auto refresh MIDI sources failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func stopLifecycleLocked(state: inout BluetoothMIDILifecycleState) {
        disconnectAllSources(state: &state)

        if state.midi1InputPortRef != 0 {
            MIDIPortDispose(state.midi1InputPortRef)
            state.midi1InputPortRef = 0
        }
        if state.midi2InputPortRef != 0 {
            MIDIPortDispose(state.midi2InputPortRef)
            state.midi2InputPortRef = 0
        }
        if state.clientRef != 0 {
            MIDIClientDispose(state.clientRef)
            state.clientRef = 0
        }
    }

    private func disconnectAllSources(state: inout BluetoothMIDILifecycleState) {
        for source in state.connectedSources {
            MIDIPortDisconnectSource(source.portRef, source.endpoint)
        }
        state.connectedSources.removeAll(keepingCapacity: false)
    }

    private func handleEventList(_ eventList: UnsafePointer<MIDIEventList>, srcConnRefCon: UnsafeMutableRawPointer?) {
        guard stateLock.withLock({ $0.isRunning }) else { return }
        let protocolID = eventList.pointee.protocol
        var context = MIDIEventListVisitorContext(
            service: self,
            protocolID: protocolID,
            srcConnRefCon: srcConnRefCon
        )
        withUnsafeMutablePointer(to: &context) { pointer in
            MIDIEventListForEachEvent(eventList, midiEventVisitor, UnsafeMutableRawPointer(pointer))
        }
    }

    fileprivate func handleUniversalMessage(
        _ message: MIDIUniversalMessage,
        timeStamp _: MIDITimeStamp,
        protocolID: MIDIProtocolID,
        srcConnRefCon: UnsafeMutableRawPointer?
    ) {
        guard stateLock.withLock({ $0.isRunning }) else { return }
        let receivedAt = Date.now
        let receivedAtUptimeSeconds = ProcessInfo.processInfo.systemUptime
        let source = sourceIdentity(from: srcConnRefCon)
        let group = Int(message.group)

        switch message.type {
        case .channelVoice1:
            if protocolID != ._1_0 {
                logProtocolMismatchIfNeeded(
                    uptimeSeconds: receivedAtUptimeSeconds,
                    expected: ._1_0,
                    actual: protocolID,
                    messageType: "channelVoice1"
                )
            }

            let voice = message.channelVoice1
            let channel = Int(voice.channel) + 1
            guard let kind = midi1Decoder.decode(message) else { return }
            midi1EventsBroadcaster.yield(MIDI1InputEvent(
                kind: kind,
                channel: channel,
                group: group,
                source: source,
                receivedAt: receivedAt,
                receivedAtUptimeSeconds: receivedAtUptimeSeconds
            ))

        case .channelVoice2:
            if protocolID != ._2_0 {
                logProtocolMismatchIfNeeded(
                    uptimeSeconds: receivedAtUptimeSeconds,
                    expected: ._2_0,
                    actual: protocolID,
                    messageType: "channelVoice2"
                )
            }

            let voice = message.channelVoice2
            let channel = Int(voice.channel) + 1
            guard let kind = midi2Decoder.decode(message) else { return }

            midi2EventsBroadcaster.yield(MIDI2InputEvent(
                kind: kind,
                channel: channel,
                group: group,
                source: midi2Source(from: source),
                receivedAt: receivedAt,
                receivedAtUptimeSeconds: receivedAtUptimeSeconds
            ))

        default:
            return
        }
    }

    private func describeEndpoint(_ endpoint: MIDIEndpointRef) -> String? {
        let name = MIDIEndpointPropertyReader.stringProperty(endpoint, kMIDIPropertyName) ?? "unknown"
        let manufacturer = MIDIEndpointPropertyReader.stringProperty(endpoint, kMIDIPropertyManufacturer)
        let model = MIDIEndpointPropertyReader.stringProperty(endpoint, kMIDIPropertyModel)
        let protocolID = MIDIEndpointPropertyReader.int32Property(endpoint, kMIDIPropertyProtocolID)
        let uniqueID = MIDIEndpointPropertyReader.int32Property(endpoint, kMIDIPropertyUniqueID)

        var parts = ["name=\(name)"]
        if let manufacturer { parts.append("manufacturer=\(manufacturer)") }
        if let model { parts.append("model=\(model)") }
        if let protocolID { parts.append("protocolID=\(protocolID)") }
        if let uniqueID { parts.append("uniqueID=\(uniqueID)") }
        return parts.joined(separator: ",")
    }

    private func sourceIdentity(from srcConnRefCon: UnsafeMutableRawPointer?) -> MIDI1InputEvent.Source {
        guard let srcConnRefCon else {
            return MIDI1InputEvent.Source(identifier: .sourceIndex(-1), endpointName: nil)
        }

        let context = Unmanaged<EndpointConnectionContext>
            .fromOpaque(srcConnRefCon)
            .takeUnretainedValue()
        if let uniqueID = context.endpointUniqueID {
            return MIDI1InputEvent.Source(
                identifier: .endpointUniqueID(uniqueID),
                endpointName: context.endpointName
            )
        }
        return MIDI1InputEvent.Source(
            identifier: .sourceIndex(context.sourceIndex),
            endpointName: context.endpointName
        )
    }

    private func midi2Source(from source: MIDI1InputEvent.Source) -> MIDI2InputEvent.Source {
        let identifier: MIDI2InputEvent.Source.Identifier = switch source.identifier {
        case let .endpointUniqueID(uniqueID):
            .endpointUniqueID(uniqueID)
        case let .sourceIndex(index):
            .sourceIndex(index)
        }
        return MIDI2InputEvent.Source(identifier: identifier, endpointName: source.endpointName)
    }







    private func logProtocolMismatchIfNeeded(
        uptimeSeconds: TimeInterval,
        expected: MIDIProtocolID,
        actual: MIDIProtocolID,
        messageType: String
    ) {
        let shouldLog = stateLock.withLock { state in
            if uptimeSeconds - state.lastProtocolMismatchLoggedAtUptimeSeconds < 2 {
                return false
            }
            state.lastProtocolMismatchLoggedAtUptimeSeconds = uptimeSeconds
            return true
        }
        guard shouldLog else { return }

        lifecycleLogger.warning(
            "Observed protocol mismatch for \(messageType, privacy: .public): expected=\(expected.rawValue, privacy: .public) actual=\(actual.rawValue, privacy: .public)"
        )
    }




}

private struct BluetoothMIDILifecycleState {
    var clientRef: MIDIClientRef = 0
    var midi1InputPortRef: MIDIPortRef = 0
    var midi2InputPortRef: MIDIPortRef = 0
    var connectedSources: [ConnectedSource] = []
}

private struct BluetoothMIDIInputEventSourceState {
    var isRunning = false
    var lastProtocolMismatchLoggedAtUptimeSeconds: TimeInterval = 0
}

private final class EndpointConnectionContext: Sendable {
    let sourceIndex: Int
    let endpointUniqueID: Int32?
    let endpointName: String?

    init(sourceIndex: Int, endpointUniqueID: Int32?, endpointName: String?) {
        self.sourceIndex = sourceIndex
        self.endpointUniqueID = endpointUniqueID
        self.endpointName = endpointName
    }
}

private struct ConnectedSource {
    let portRef: MIDIPortRef
    let endpoint: MIDIEndpointRef
    let connectionContext: EndpointConnectionContext
}

private struct MIDIEventListVisitorContext {
    let service: BluetoothMIDIInputEventSourceService
    let protocolID: MIDIProtocolID
    let srcConnRefCon: UnsafeMutableRawPointer?
}

private func midiEventVisitor(
    context: UnsafeMutableRawPointer?,
    timeStamp: MIDITimeStamp,
    message: MIDIUniversalMessage
) {
    guard let context else { return }
    let typed = context.assumingMemoryBound(to: MIDIEventListVisitorContext.self).pointee
    typed.service.handleUniversalMessage(
        message,
        timeStamp: timeStamp,
        protocolID: typed.protocolID,
        srcConnRefCon: typed.srcConnRefCon
    )
}
