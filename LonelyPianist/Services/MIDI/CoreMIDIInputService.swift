import CoreMIDI
import Foundation
import OSLog

enum MIDIInputServiceError: LocalizedError {
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

final class CoreMIDIInputService: MIDIInputServiceProtocol {
    var onEvent: (@Sendable (MIDIEvent) -> Void)?
    var onConnectionStateChange: (@Sendable (MIDIInputConnectionState) -> Void)?
    var onSourceNamesChange: (@Sendable ([String]) -> Void)?

    private let logger = Logger(subsystem: "com.chiimagnus.LonelyPianist", category: "CoreMIDI")

    private var clientRef: MIDIClientRef = 0
    private var inputPortRef: MIDIPortRef = 0
    private var connectedSources: [MIDIEndpointRef] = []
    private var isRunning = false
    private var didLogNonNoteMessage = false

    deinit {
        stop()
    }

    func start() throws {
        guard !isRunning else { return }

        try createClientIfNeeded()
        try createInputPortIfNeeded()
        try refreshSources()

        isRunning = true
        logger.info("MIDI listening started")
    }

    func stop() {
        disconnectAllSources()

        if inputPortRef != 0 {
            MIDIPortDispose(inputPortRef)
            inputPortRef = 0
        }

        if clientRef != 0 {
            MIDIClientDispose(clientRef)
            clientRef = 0
        }

        isRunning = false
        onConnectionStateChange?(.idle)
        logger.info("MIDI listening stopped")
    }

    func refreshSources() throws {
        guard inputPortRef != 0 else {
            onConnectionStateChange?(.failed("MIDI input port is unavailable"))
            return
        }

        disconnectAllSources()

        var failedStatus: OSStatus?
        let sourceCount = MIDIGetNumberOfSources()

        for index in 0 ..< sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }

            let status = MIDIPortConnectSource(inputPortRef, source, nil)
            if status == noErr {
                connectedSources.append(source)
            } else {
                failedStatus = status
                logger.error("Failed to connect source \(index, privacy: .public): \(status, privacy: .public)")
            }
        }

        if connectedSources.isEmpty {
            onSourceNamesChange?([])
            if let failedStatus {
                onConnectionStateChange?(.failed("No MIDI source connected (status: \(failedStatus))"))
                throw MIDIInputServiceError.sourceRefresh(failedStatus)
            }
            onConnectionStateChange?(.connected(sourceCount: 0))
            logger.info("MIDI source refresh finished with zero connected source")
            return
        }

        let sourceNames = connectedSources.map(endpointName)
        onSourceNamesChange?(sourceNames)

        onConnectionStateChange?(.connected(sourceCount: connectedSources.count))
        logger.info("MIDI connected source count: \(self.connectedSources.count, privacy: .public)")
    }

    private func createClientIfNeeded() throws {
        guard clientRef == 0 else { return }

        let status = MIDIClientCreate(
            "LonelyPianistMIDIClient" as CFString,
            nil,
            nil,
            &clientRef
        )

        guard status == noErr else {
            onConnectionStateChange?(.failed("Create MIDI client failed: \(status)"))
            throw MIDIInputServiceError.clientCreate(status)
        }
    }

    private func createInputPortIfNeeded() throws {
        guard inputPortRef == 0 else { return }

        let status = MIDIInputPortCreateWithProtocol(
            clientRef,
            "LonelyPianistMIDIInput" as CFString,
            MIDIProtocolID._1_0,
            &inputPortRef
        ) { [weak self] eventList, _ in
            self?.handleEventList(eventList)
        }

        guard status == noErr else {
            onConnectionStateChange?(.failed("Create MIDI input port failed: \(status)"))
            throw MIDIInputServiceError.portCreate(status)
        }
    }

    private func disconnectAllSources() {
        for source in connectedSources {
            MIDIPortDisconnectSource(inputPortRef, source)
        }
        connectedSources.removeAll(keepingCapacity: false)
        didLogNonNoteMessage = false
        onSourceNamesChange?([])
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

        return "Unknown MIDI Source"
    }

    private func handleEventList(_ eventList: UnsafePointer<MIDIEventList>) {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        MIDIEventListForEachEvent(eventList, midiEventVisitor, context)
    }

    fileprivate func handleUniversalMessage(
        _ message: MIDIUniversalMessage,
        timeStamp _: MIDITimeStamp
    ) {
        switch message.type {
            case .channelVoice1:
                let status = message.channelVoice1.status
                guard status == .noteOn || status == .noteOff || status == .controlChange else {
                    if !didLogNonNoteMessage {
                        logger.info("Receiving MIDI data, but no note-on/off yet")
                        didLogNonNoteMessage = true
                    }
                    return
                }

                let channel = Int(message.channelVoice1.channel) + 1
                switch status {
                    case .controlChange:
                        let controller = Int(message.channelVoice1.controlChange.index)
                        let value = Int(message.channelVoice1.controlChange.data)
                        emitEvent(type: .controlChange(controller: controller, value: value), channel: channel)

                    case .noteOn, .noteOff:
                        let note = Int(message.channelVoice1.note.number)
                        let velocity = Int(message.channelVoice1.note.velocity)
                        let eventType: MIDIEvent.EventType =
                            (status == .noteOn && velocity > 0)
                                ? .noteOn(note: note, velocity: velocity)
                                : .noteOff(note: note, velocity: velocity)
                        emitEvent(type: eventType, channel: channel)

                    default:
                        break
                }

            case .channelVoice2:
                let status = message.channelVoice2.status
                guard status == .noteOn || status == .noteOff || status == .controlChange else {
                    if !didLogNonNoteMessage {
                        logger.info("Receiving MIDI 2.0 data, but no note-on/off yet")
                        didLogNonNoteMessage = true
                    }
                    return
                }

                let channel = Int(message.channelVoice2.channel) + 1
                switch status {
                    case .controlChange:
                        let controller = Int(message.channelVoice2.controlChange.index)
                        let value32 = Double(message.channelVoice2.controlChange.data)
                        let normalized = Int((value32 / Double(UInt32.max)) * 127.0)
                        let value = max(0, min(127, normalized))
                        emitEvent(type: .controlChange(controller: controller, value: value), channel: channel)

                    case .noteOn, .noteOff:
                        let note = Int(message.channelVoice2.note.number)
                        let velocity16 = Int(message.channelVoice2.note.velocity)
                        let velocity = Int((Double(velocity16) / 65535.0) * 127.0)
                        let eventType: MIDIEvent.EventType =
                            (status == .noteOn && velocity16 > 0)
                                ? .noteOn(note: note, velocity: velocity)
                                : .noteOff(note: note, velocity: velocity)
                        emitEvent(type: eventType, channel: channel)

                    default:
                        break
                }

            default:
                break
        }
    }

    private func emitEvent(
        type: MIDIEvent.EventType,
        channel: Int
    ) {
        let clampedChannel = max(1, channel)

        let clampedType: MIDIEvent.EventType = switch type {
            case let .noteOn(note, velocity):
                .noteOn(
                    note: max(0, min(127, note)),
                    velocity: max(0, min(127, velocity))
                )
            case let .noteOff(note, velocity):
                .noteOff(
                    note: max(0, min(127, note)),
                    velocity: max(0, min(127, velocity))
                )
            case let .controlChange(controller, value):
                .controlChange(
                    controller: max(0, min(127, controller)),
                    value: max(0, min(127, value))
                )
        }

        let event = MIDIEvent(type: clampedType, channel: clampedChannel, timestamp: Date())
        onEvent?(event)
    }
}

private func midiEventVisitor(
    context: UnsafeMutableRawPointer?,
    timeStamp: MIDITimeStamp,
    message: MIDIUniversalMessage
) {
    guard let context else { return }
    let service = Unmanaged<CoreMIDIInputService>.fromOpaque(context).takeUnretainedValue()
    service.handleUniversalMessage(message, timeStamp: timeStamp)
}
