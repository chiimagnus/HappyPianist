import CoreMIDI
import Foundation
import OSLog
import os

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

final class BluetoothMIDIInputEventSourceService: PracticeInputEventSourceProtocol {
    func midi1EventsStream() -> AsyncStream<MIDI1InputEvent> {
        midi1EventsBroadcaster.makeStream()
    }

    func midi2EventsStream() -> AsyncStream<MIDI2InputEvent> {
        midi2EventsBroadcaster.makeStream()
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "BluetoothMIDI"
    )
    private let midi1Logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "BluetoothMIDI-MIDI1"
    )
    private let midi2Logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "BluetoothMIDI-MIDI2"
    )
    private let refreshScheduler = DebouncedActionScheduler(queue: .main, debounceSec: 0.2)

    private var clientRef: MIDIClientRef = 0
    private var midi1InputPortRef: MIDIPortRef = 0
    private var midi2InputPortRef: MIDIPortRef = 0
    private var connectedSources: [ConnectedSource] = []
    private var connectedSourceDescriptions: [String] = []
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
            state.eventListProtocolCounts.removeAll(keepingCapacity: true)
            state.midi1MessageTypeCounts.removeAll(keepingCapacity: true)
            state.midi2MessageTypeCounts.removeAll(keepingCapacity: true)
            state.otherMessageTypeCounts.removeAll(keepingCapacity: true)
            state.midi1DeliveriesBySource.removeAll(keepingCapacity: true)
            state.midi2DeliveriesBySource.removeAll(keepingCapacity: true)
            state.protocolMismatchDropCounts.removeAll(keepingCapacity: true)
            state.lastEventListDebugLoggedAtUptimeSeconds = 0
            state.nextDebugEventID = 1
            return true
        }
        guard shouldStart else { return }

        try createClientIfNeeded()
        try createMIDI1InputPortIfNeeded()
        try createMIDI2InputPortIfNeeded()
        try refreshSources()
    }

    func stop() {
        stateLock.withLock { state in
            state.isRunning = false
        }
        refreshScheduler.cancel()

        disconnectAllSources()
        logEventDeliveryDebugSummary(reason: "stop")

        if midi1InputPortRef != 0 {
            MIDIPortDispose(midi1InputPortRef)
            midi1InputPortRef = 0
        }

        if midi2InputPortRef != 0 {
            MIDIPortDispose(midi2InputPortRef)
            midi2InputPortRef = 0
        }

        if clientRef != 0 {
            MIDIClientDispose(clientRef)
            clientRef = 0
        }
    }

    func refreshSources() throws {
        guard midi1InputPortRef != 0 || midi2InputPortRef != 0 else { return }

        disconnectAllSources()
        connectedSourceDescriptions.removeAll(keepingCapacity: false)

        var failedStatus: OSStatus?
        let sourceCount = MIDIGetNumberOfSources()

        for index in 0 ..< sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }

            let endpointName = endpointStringProperty(source, kMIDIPropertyDisplayName) ??
                endpointStringProperty(source, kMIDIPropertyName)
            let endpointUniqueID = endpointIntProperty(source, kMIDIPropertyUniqueID)
            let connectionContext = EndpointConnectionContext(
                sourceIndex: index,
                endpointUniqueID: endpointUniqueID,
                endpointName: endpointName
            )
            let connRefCon = UnsafeMutableRawPointer(Unmanaged.passRetained(connectionContext).toOpaque())

            let endpointProtocolID = endpointIntProperty(source, kMIDIPropertyProtocolID).flatMap(MIDIProtocolID.init(rawValue:))
            if endpointProtocolID == ._2_0, midi2InputPortRef == 0 {
                logger.warning("Endpoint reports MIDI 2.0 but MIDI 2.0 port is unavailable; subscribing via MIDI 1.0 port: \(self.describeEndpoint(source) ?? "unknown", privacy: .public)")
            }
            let targetProtocol = MIDICanonicalProtocolSelection.subscribedProtocol(
                endpointProtocolID: endpointProtocolID,
                midi2PortAvailable: midi2InputPortRef != 0
            )
            let targetPortRef = targetProtocol == ._2_0 ? midi2InputPortRef : midi1InputPortRef

            let status = MIDIPortConnectSource(targetPortRef, source, connRefCon)
            if status == noErr {
                connectedSources.append(ConnectedSource(portRef: targetPortRef, endpoint: source, connRefCon: connRefCon))
                let subscribed = targetProtocol == ._2_0 ? "midi2" : "midi1"
                let description = (describeEndpoint(source) ?? "sourceIndex=\(index)") + ",subscribed=\(subscribed)"
                connectedSourceDescriptions.append(description)
            } else {
                Unmanaged<EndpointConnectionContext>.fromOpaque(connRefCon).release()
                failedStatus = status
                logger.error("Failed to connect source \(index, privacy: .public): \(status, privacy: .public)")
            }
        }

        if connectedSourceDescriptions.isEmpty == false {
            logger.info("Connected MIDI sources: \(self.connectedSourceDescriptions.joined(separator: " | "), privacy: .public)")
        }

        if connectedSources.isEmpty, let failedStatus {
            throw BluetoothMIDIInputEventSourceServiceError.sourceRefresh(failedStatus)
        }

        // Log initial delivery summary after refresh to help spot protocol switching early.
        logEventDeliveryDebugSummary(reason: "refreshSources")
    }

    private func createClientIfNeeded() throws {
        guard clientRef == 0 else { return }

        let status = MIDIClientCreateWithBlock(
            "LonelyPianistAVPBluetoothMIDIEventsClient" as CFString,
            &clientRef
        ) { [weak self] message in
            let notification = message.pointee
            Task { @MainActor [weak self] in
                self?.handleMIDINotification(notification)
            }
        }

        guard status == noErr else {
            throw BluetoothMIDIInputEventSourceServiceError.clientCreate(status)
        }
    }

    private func createMIDI1InputPortIfNeeded() throws {
        guard midi1InputPortRef == 0 else { return }

        let status = MIDIInputPortCreateWithProtocol(
            clientRef,
            "LonelyPianistAVPBluetoothMIDIEventsInput-MIDI1" as CFString,
            MIDIProtocolID._1_0,
            &midi1InputPortRef
        ) { [weak self] eventList, srcConnRefCon in
            guard let self else { return }
            self.handleEventList(eventList, srcConnRefCon: srcConnRefCon)
        }

        guard status == noErr else {
            throw BluetoothMIDIInputEventSourceServiceError.portCreate(status)
        }
    }

    private func createMIDI2InputPortIfNeeded() throws {
        guard midi2InputPortRef == 0 else { return }

        let status = MIDIInputPortCreateWithProtocol(
            clientRef,
            "LonelyPianistAVPBluetoothMIDIEventsInput-MIDI2" as CFString,
            MIDIProtocolID._2_0,
            &midi2InputPortRef
        ) { [weak self] eventList, srcConnRefCon in
            guard let self else { return }
            self.handleEventList(eventList, srcConnRefCon: srcConnRefCon)
        }

        if status != noErr {
            logger.warning("Failed to create MIDI 2.0 input port, falling back to MIDI 1.0 only: \(status, privacy: .public)")
            midi2InputPortRef = 0
        }
    }

    private func handleMIDINotification(_ notification: MIDINotification) {
        _ = notification
        scheduleRefreshSources()
    }

    private func scheduleRefreshSources() {
        guard stateLock.withLock({ $0.isRunning }) else { return }
        refreshScheduler.schedule { [weak self] in
            guard let self else { return }
            guard self.stateLock.withLock({ $0.isRunning }), (self.midi1InputPortRef != 0 || self.midi2InputPortRef != 0) else { return }

            do {
                try self.refreshSources()
            } catch {
                self.logger.error("Auto refresh MIDI sources failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func disconnectAllSources() {
        for source in connectedSources {
            MIDIPortDisconnectSource(source.portRef, source.endpoint)
            source.releaseConnRefConIfNeeded()
        }
        connectedSources.removeAll(keepingCapacity: false)
        connectedSourceDescriptions.removeAll(keepingCapacity: false)
    }

    private func handleEventList(_ eventList: UnsafePointer<MIDIEventList>, srcConnRefCon: UnsafeMutableRawPointer?) {
        guard stateLock.withLock({ $0.isRunning }) else { return }
        recordEventListProtocolAndMessageTypes(eventList: eventList)
        let protocolID = eventList.pointee.`protocol`
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
        let receivedAt = Date()
        let receivedAtUptimeSeconds = ProcessInfo.processInfo.systemUptime
        let source = sourceIdentity(from: srcConnRefCon)
        let group = Int(message.group)

        switch message.type {
        case .channelVoice1:
            stateLock.withLock { state in
                state.midi1MessageTypeCounts["channelVoice1", default: 0] += 1
            }
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
            let debugEventID = nextDebugEventID()
            recordDelivery(protocolID: protocolID, source: source)
            midi1EventsBroadcaster.yield(MIDI1InputEvent(
                kind: kind,
                channel: channel,
                group: group,
                source: source,
                receivedAt: receivedAt,
                receivedAtUptimeSeconds: receivedAtUptimeSeconds,
                debugEventID: debugEventID
            ))

        case .channelVoice2:
            stateLock.withLock { state in
                state.midi2MessageTypeCounts["channelVoice2", default: 0] += 1
            }
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
            let debugEventID = nextDebugEventID()
            recordDelivery(protocolID: protocolID, source: source)

            midi2EventsBroadcaster.yield(MIDI2InputEvent(
                kind: kind,
                channel: channel,
                group: group,
                source: midi2Source(from: source),
                receivedAt: receivedAt,
                receivedAtUptimeSeconds: receivedAtUptimeSeconds,
                debugEventID: debugEventID
            ))

        default:
            stateLock.withLock { state in
                state.otherMessageTypeCounts["other", default: 0] += 1
            }
            break
        }
    }

    private func describeEndpoint(_ endpoint: MIDIEndpointRef) -> String? {
        let name = endpointStringProperty(endpoint, kMIDIPropertyName) ?? "unknown"
        let manufacturer = endpointStringProperty(endpoint, kMIDIPropertyManufacturer)
        let model = endpointStringProperty(endpoint, kMIDIPropertyModel)
        let protocolID = endpointIntProperty(endpoint, kMIDIPropertyProtocolID)
        let uniqueID = endpointIntProperty(endpoint, kMIDIPropertyUniqueID)

        var parts: [String] = ["name=\(name)"]
        if let manufacturer { parts.append("manufacturer=\(manufacturer)") }
        if let model { parts.append("model=\(model)") }
        if let protocolID { parts.append("protocolID=\(protocolID)") }
        if let uniqueID { parts.append("uniqueID=\(uniqueID)") }
        return parts.joined(separator: ",")
    }

    private func endpointStringProperty(_ endpoint: MIDIEndpointRef, _ property: CFString) -> String? {
        var unmanagedValue: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, property, &unmanagedValue)
        guard status == noErr, let unmanagedValue else { return nil }
        return unmanagedValue.takeRetainedValue() as String
    }

    private func endpointIntProperty(_ endpoint: MIDIEndpointRef, _ property: CFString) -> Int32? {
        var value: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(endpoint, property, &value)
        guard status == noErr else { return nil }
        return value
    }

    private func sourceIdentity(from srcConnRefCon: UnsafeMutableRawPointer?) -> MIDI1InputEvent.Source {
        guard let srcConnRefCon else {
            return MIDI1InputEvent.Source(identifier: .sourceIndex(-1), endpointName: nil)
        }

        let context = Unmanaged<EndpointConnectionContext>.fromOpaque(srcConnRefCon).takeUnretainedValue()
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

    private func recordDelivery(protocolID: MIDIProtocolID, source: MIDI1InputEvent.Source) {
        let key = sourceKey(for: source)
        stateLock.withLock { state in
            switch protocolID {
            case ._1_0:
                state.midi1DeliveriesBySource[key, default: 0] += 1
            case ._2_0:
                state.midi2DeliveriesBySource[key, default: 0] += 1
            default:
                break
            }
        }
    }

    private func sourceKey(for source: MIDI1InputEvent.Source) -> String {
        let base: String = switch source.identifier {
        case let .endpointUniqueID(uniqueID):
            "uid=\(uniqueID)"
        case let .sourceIndex(index):
            "idx=\(index)"
        }
        if let name = source.endpointName, name.isEmpty == false {
            return "\(base)(\(name))"
        }
        return base
    }

    private func nextDebugEventID() -> Int64 {
        stateLock.withLock { state in
            defer { state.nextDebugEventID += 1 }
            return state.nextDebugEventID
        }
    }

    private func logProtocolMismatchIfNeeded(
        uptimeSeconds: TimeInterval,
        expected: MIDIProtocolID,
        actual: MIDIProtocolID,
        messageType: String
    ) {
        let shouldLog = stateLock.withLock { state in
            let key = "\(messageType) expected=\(expected.rawValue) actual=\(actual.rawValue)"
            state.protocolMismatchDropCounts[key, default: 0] += 1
            if uptimeSeconds - state.lastProtocolMismatchLoggedAtUptimeSeconds < 2 {
                return false
            }
            state.lastProtocolMismatchLoggedAtUptimeSeconds = uptimeSeconds
            return true
        }
        guard shouldLog else { return }

        logger.warning(
            "Observed protocol mismatch for \(messageType, privacy: .public): expected=\(expected.rawValue, privacy: .public) actual=\(actual.rawValue, privacy: .public)"
        )
    }

    private func recordEventListProtocolAndMessageTypes(eventList: UnsafePointer<MIDIEventList>) {
        let uptimeSeconds = ProcessInfo.processInfo.systemUptime
        let protocolID = eventList.pointee.`protocol`.rawValue
        let shouldLog = stateLock.withLock { state in
            state.eventListProtocolCounts[protocolID, default: 0] += 1
            if uptimeSeconds - state.lastEventListDebugLoggedAtUptimeSeconds >= 2 {
                state.lastEventListDebugLoggedAtUptimeSeconds = uptimeSeconds
                return true
            }
            return false
        }

        if shouldLog {
            logEventDeliveryDebugSummary(reason: "periodic")
        }
    }

    private func logEventDeliveryDebugSummary(reason: String) {
        let snapshot = stateLock.withLock { state in
            (
                state.eventListProtocolCounts,
                state.midi1MessageTypeCounts,
                state.midi2MessageTypeCounts,
                state.midi1DeliveriesBySource,
                state.midi2DeliveriesBySource,
                state.protocolMismatchDropCounts
            )
        }
        let eventListProtocolCounts = snapshot.0
        let midi1Types = snapshot.1
        let midi2Types = snapshot.2
        let midi1Sources = snapshot.3
        let midi2Sources = snapshot.4
        let drops = snapshot.5
        guard eventListProtocolCounts.isEmpty == false ||
            midi1Types.isEmpty == false ||
            midi2Types.isEmpty == false ||
            midi1Sources.isEmpty == false ||
            midi2Sources.isEmpty == false ||
            drops.isEmpty == false else { return }

        func format(_ dict: [String: Int]) -> String {
            dict.sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ",")
        }

        let protocols = eventListProtocolCounts
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")

        logger.info(
            "MIDI delivery summary (\(reason, privacy: .public)): eventListProtocols{\(protocols, privacy: .public)} midi1Types{\(format(midi1Types), privacy: .public)} midi1Sources{\(format(midi1Sources), privacy: .public)} midi2Types{\(format(midi2Types), privacy: .public)} midi2Sources{\(format(midi2Sources), privacy: .public)} drops{\(format(drops), privacy: .public)}"
        )
    }
}

private struct BluetoothMIDIInputEventSourceState {
    var isRunning: Bool = false
    var eventListProtocolCounts: [Int32: Int] = [:]
    var midi1MessageTypeCounts: [String: Int] = [:]
    var midi2MessageTypeCounts: [String: Int] = [:]
    var otherMessageTypeCounts: [String: Int] = [:]
    var midi1DeliveriesBySource: [String: Int] = [:]
    var midi2DeliveriesBySource: [String: Int] = [:]
    var protocolMismatchDropCounts: [String: Int] = [:]
    var lastEventListDebugLoggedAtUptimeSeconds: TimeInterval = 0
    var nextDebugEventID: Int64 = 1
    var lastProtocolMismatchLoggedAtUptimeSeconds: TimeInterval = 0
}

private final class EndpointConnectionContext {
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
    let connRefCon: UnsafeMutableRawPointer?

    func releaseConnRefConIfNeeded() {
        guard let connRefCon else { return }
        Unmanaged<EndpointConnectionContext>.fromOpaque(connRefCon).release()
    }
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
