import CoreMIDI
import Foundation
import OSLog

enum MIDIInputServiceError: LocalizedError {
    case clientCreate(OSStatus)
    case portCreate(OSStatus)
    case sourceRefresh(OSStatus)

    var errorDescription: String? {
        switch self {
        case .clientCreate(let status):
            return "Failed to create MIDI client: \(status)"
        case .portCreate(let status):
            return "Failed to create MIDI input port: \(status)"
        case .sourceRefresh(let status):
            return "Failed to refresh MIDI sources: \(status)"
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

        for index in 0..<sourceCount {
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
        timeStamp: MIDITimeStamp
    ) {
        switch message.type {
        case .channelVoice1:
            let status = message.channelVoice1.status
            guard status == .noteOn || status == .noteOff else {
                if !didLogNonNoteMessage {
                    logger.info("Receiving MIDI data, but no note-on/off yet")
                    didLogNonNoteMessage = true
                }
                return
            }

            let note = Int(message.channelVoice1.note.number)
            let velocity = Int(message.channelVoice1.note.velocity)
            let channel = Int(message.channelVoice1.channel) + 1
            let eventType: MIDIEvent.EventType = (status == .noteOn && velocity > 0) ? .noteOn : .noteOff
            emitEvent(type: eventType, note: note, velocity: velocity, channel: channel)

        case .channelVoice2:
            let status = message.channelVoice2.status
            guard status == .noteOn || status == .noteOff else {
                if !didLogNonNoteMessage {
                    logger.info("Receiving MIDI 2.0 data, but no note-on/off yet")
                    didLogNonNoteMessage = true
                }
                return
            }

            let note = Int(message.channelVoice2.note.number)
            let velocity16 = Int(message.channelVoice2.note.velocity)
            let velocity = Int((Double(velocity16) / 65535.0) * 127.0)
            let channel = Int(message.channelVoice2.channel) + 1
            let eventType: MIDIEvent.EventType = (status == .noteOn && velocity16 > 0) ? .noteOn : .noteOff
            emitEvent(type: eventType, note: note, velocity: velocity, channel: channel)

        default:
            break
        }
    }

    private func emitEvent(
        type: MIDIEvent.EventType,
        note: Int,
        velocity: Int,
        channel: Int
    ) {
        let event = MIDIEvent(
            type: type,
            note: max(0, min(127, note)),
            velocity: max(0, min(127, velocity)),
            channel: max(1, channel),
            timestamp: Date()
        )
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
