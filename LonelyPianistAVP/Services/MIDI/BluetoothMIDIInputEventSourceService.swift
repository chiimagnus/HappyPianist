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
    func eventsStream() -> AsyncStream<PracticeInputEvent> {
        eventsBroadcaster.makeStream()
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "BluetoothMIDI-Events"
    )
    private let refreshScheduler = DebouncedActionScheduler(queue: .main, debounceSec: 0.2)

    private var clientRef: MIDIClientRef = 0
    private var inputPortRef: MIDIPortRef = 0
    private var connectedSources: [MIDIEndpointRef] = []
    private var connectedSourceDescriptions: [String] = []
    private let stateLock = OSAllocatedUnfairLock(initialState: BluetoothMIDIInputEventSourceState())

    private let eventsBroadcaster = PracticeInputEventBroadcaster()

    init() {}

    func start() throws {
        let shouldStart = stateLock.withLock { state in
            if state.isRunning { return false }
            state.isRunning = true
            state.eventListProtocolCounts.removeAll(keepingCapacity: true)
            state.messageTypeCounts.removeAll(keepingCapacity: true)
            state.lastEventListDebugLoggedAtUptimeSeconds = 0
            state.nextDebugEventID = 1
            return true
        }
        guard shouldStart else { return }

        try createClientIfNeeded()
        try createInputPortIfNeeded()
        try refreshSources()
    }

    func stop() {
        stateLock.withLock { state in
            state.isRunning = false
        }
        refreshScheduler.cancel()

        disconnectAllSources()
        logEventDeliveryDebugSummary(reason: "stop")

        if inputPortRef != 0 {
            MIDIPortDispose(inputPortRef)
            inputPortRef = 0
        }

        if clientRef != 0 {
            MIDIClientDispose(clientRef)
            clientRef = 0
        }
    }

    func refreshSources() throws {
        guard inputPortRef != 0 else { return }

        disconnectAllSources()
        connectedSourceDescriptions.removeAll(keepingCapacity: false)

        var failedStatus: OSStatus?
        let sourceCount = MIDIGetNumberOfSources()

        for index in 0 ..< sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }

            let status = MIDIPortConnectSource(inputPortRef, source, nil)
            if status == noErr {
                connectedSources.append(source)
                let description = describeEndpoint(source) ?? "sourceIndex=\(index)"
                connectedSourceDescriptions.append(description)
            } else {
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

    private func createInputPortIfNeeded() throws {
        guard inputPortRef == 0 else { return }

        let status = MIDIInputPortCreateWithProtocol(
            clientRef,
            "LonelyPianistAVPBluetoothMIDIEventsInput" as CFString,
            MIDIProtocolID._1_0,
            &inputPortRef
        ) { [weak self] eventList, _ in
            guard let self else { return }
            self.handleEventList(eventList)
        }

        guard status == noErr else {
            throw BluetoothMIDIInputEventSourceServiceError.portCreate(status)
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
            guard self.stateLock.withLock({ $0.isRunning }), self.inputPortRef != 0 else { return }

            do {
                try self.refreshSources()
            } catch {
                self.logger.error("Auto refresh MIDI sources failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func disconnectAllSources() {
        for source in connectedSources {
            MIDIPortDisconnectSource(inputPortRef, source)
        }
        connectedSources.removeAll(keepingCapacity: false)
        connectedSourceDescriptions.removeAll(keepingCapacity: false)
    }

    private func handleEventList(_ eventList: UnsafePointer<MIDIEventList>) {
        guard stateLock.withLock({ $0.isRunning }) else { return }
        recordEventListProtocolAndMessageTypes(eventList: eventList)
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        MIDIEventListForEachEvent(eventList, midiEventVisitor, context)
    }

    fileprivate func handleUniversalMessage(
        _ message: MIDIUniversalMessage,
        timeStamp _: MIDITimeStamp
    ) {
        guard stateLock.withLock({ $0.isRunning }) else { return }
        let receivedAt = Date()
        let receivedAtUptimeSeconds = ProcessInfo.processInfo.systemUptime

        switch message.type {
        case .channelVoice1:
            stateLock.withLock { state in
                state.messageTypeCounts["channelVoice1", default: 0] += 1
            }
            let voice = message.channelVoice1
            let channel = Int(voice.channel) + 1

            switch voice.status {
            case .noteOn:
                let note = Int(voice.note.number)
                let velocity = Int(voice.note.velocity)
                let kind: PracticeInputEvent.Kind = velocity > 0 ? .noteOn(note: note, velocity: velocity) : .noteOff(note: note, velocity: 0)
                publish(kind, channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            case .noteOff:
                let note = Int(voice.note.number)
                let velocity = Int(voice.note.velocity)
                publish(.noteOff(note: note, velocity: velocity), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            case .controlChange:
                let controller = Int(voice.controlChange.index)
                let value = Int(voice.controlChange.data)
                publish(.controlChange(controller: controller, value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            case .programChange:
                let program = Int(voice.program)
                publish(.programChange(program: program), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            case .channelPressure:
                let value = Int(voice.channelPressure)
                publish(.channelPressure(value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            case .polyPressure:
                let note = Int(voice.polyPressure.noteNumber)
                let value = Int(voice.polyPressure.pressure)
                publish(.polyPressure(note: note, value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            case .pitchBend:
                let value = Int(voice.pitchBend)
                publish(.pitchBend(value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            default:
                break
            }

        case .channelVoice2:
            stateLock.withLock { state in
                state.messageTypeCounts["channelVoice2", default: 0] += 1
            }
            let voice = message.channelVoice2
            let channel = Int(voice.channel) + 1

            switch voice.status {
            case .noteOn:
                let note = Int(voice.note.number)
                let velocity16 = voice.note.velocity
                let velocity = scaleMIDI2Value16To127(velocity16)
                let kind: PracticeInputEvent.Kind = velocity16 > 0 ? .noteOn(note: note, velocity: velocity) : .noteOff(note: note, velocity: 0)
                publish(kind, channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            case .noteOff:
                let note = Int(voice.note.number)
                let velocity16 = voice.note.velocity
                let velocity = scaleMIDI2Value16To127(velocity16)
                publish(.noteOff(note: note, velocity: velocity), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            case .controlChange:
                let controller = Int(voice.controlChange.index)
                let value = scaleMIDI2Value32To127(UInt32(voice.controlChange.data))
                publish(.controlChange(controller: controller, value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            case .programChange:
                let program = Int(voice.programChange.program)
                publish(.programChange(program: program), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            case .channelPressure:
                let value = scaleMIDI2Value32To127(UInt32(voice.channelPressure.data))
                publish(.channelPressure(value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            case .polyPressure:
                let note = Int(voice.polyPressure.noteNumber)
                let value = scaleMIDI2Value32To127(UInt32(voice.polyPressure.pressure))
                publish(.polyPressure(note: note, value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            case .pitchBend:
                let value = scaleMIDI2PitchBendTo14Bit(UInt32(voice.pitchBend.data))
                publish(.pitchBend(value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds)

            default:
                break
            }

        default:
            stateLock.withLock { state in
                state.messageTypeCounts["other", default: 0] += 1
            }
            break
        }
    }

    private func scaleMIDI2Value16To127(_ value: UInt16) -> Int {
        // Preserve MIDI semantics: velocity 0 indicates note-off, so a non-zero MIDI 2.0 velocity
        // should never downscale to 0 in the 7-bit domain.
        guard value > 0 else { return 0 }

        // Round-to-nearest while mapping [0, 65535] -> [0, 127].
        let scaled = (Int(value) * 127 + 32767) / 65535
        return max(1, min(127, scaled))
    }

    private func scaleMIDI2Value32To127(_ value: UInt32) -> Int {
        let scaled = (Double(value) / Double(UInt32.max) * 127.0).rounded()
        return max(0, min(127, Int(scaled)))
    }

    private func scaleMIDI2PitchBendTo14Bit(_ value: UInt32) -> Int {
        let scaled = (Double(value) / Double(UInt32.max) * 16383.0).rounded()
        return max(0, min(16383, Int(scaled)))
    }

    private func publish(
        _ kind: PracticeInputEvent.Kind,
        channel: Int,
        receivedAt: Date,
        receivedAtUptimeSeconds: TimeInterval
    ) {
        let debugEventID = stateLock.withLock { state in
            defer { state.nextDebugEventID += 1 }
            return state.nextDebugEventID
        }
        eventsBroadcaster.yield(PracticeInputEvent(
            kind: kind,
            channel: channel,
            receivedAt: receivedAt,
            receivedAtUptimeSeconds: receivedAtUptimeSeconds,
            debugEventID: debugEventID
        ))
    }

    private func describeEndpoint(_ endpoint: MIDIEndpointRef) -> String? {
        let name = endpointStringProperty(endpoint, kMIDIPropertyName) ?? "unknown"
        let manufacturer = endpointStringProperty(endpoint, kMIDIPropertyManufacturer)
        let model = endpointStringProperty(endpoint, kMIDIPropertyModel)
        let protocolID = endpointIntProperty(endpoint, kMIDIPropertyProtocolID)

        var parts: [String] = ["name=\(name)"]
        if let manufacturer { parts.append("manufacturer=\(manufacturer)") }
        if let model { parts.append("model=\(model)") }
        if let protocolID { parts.append("protocolID=\(protocolID)") }
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
            (state.eventListProtocolCounts, state.messageTypeCounts)
        }
        let eventListProtocolCounts = snapshot.0
        let messageTypeCounts = snapshot.1
        guard eventListProtocolCounts.isEmpty == false || messageTypeCounts.isEmpty == false else { return }

        let protocols = eventListProtocolCounts
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        let types = messageTypeCounts
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        logger.info("MIDI delivery summary (\(reason, privacy: .public)): eventListProtocols{\(protocols, privacy: .public)} messageTypes{\(types, privacy: .public)}")
    }
}

private struct BluetoothMIDIInputEventSourceState {
    var isRunning: Bool = false
    var eventListProtocolCounts: [Int32: Int] = [:]
    var messageTypeCounts: [String: Int] = [:]
    var lastEventListDebugLoggedAtUptimeSeconds: TimeInterval = 0
    var nextDebugEventID: Int64 = 1
}

private final class PracticeInputEventBroadcaster {
    private let continuations = OSAllocatedUnfairLock(initialState: [UUID: AsyncStream<PracticeInputEvent>.Continuation]())

    func makeStream() -> AsyncStream<PracticeInputEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations.withLock { state in
                state[id] = continuation
            }
            continuation.onTermination = { @Sendable _ in
                self.continuations.withLock { state in
                    state[id] = nil
                }
            }
        }
    }

    func yield(_ event: PracticeInputEvent) {
        let snapshot = continuations.withLock { state in
            Array(state.values)
        }
        for continuation in snapshot {
            continuation.yield(event)
        }
    }
}

private func midiEventVisitor(
    context: UnsafeMutableRawPointer?,
    timeStamp: MIDITimeStamp,
    message: MIDIUniversalMessage
) {
    guard let context else { return }
    let service = Unmanaged<BluetoothMIDIInputEventSourceService>.fromOpaque(context).takeUnretainedValue()
    service.handleUniversalMessage(message, timeStamp: timeStamp)
}
