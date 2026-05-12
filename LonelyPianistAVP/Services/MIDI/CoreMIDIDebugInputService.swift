import CoreMIDI
import Foundation
import OSLog

enum MIDIDebugInputServiceError: LocalizedError {
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

final class CoreMIDIDebugInputService {
    struct NoteEvent: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case noteOn(note: Int, velocity: Int)
            case noteOff(note: Int, velocity: Int)
        }

        let kind: Kind
        let channel: Int
        let timestamp: Date
    }

    var onSourceNamesChange: (@Sendable ([String]) -> Void)?
    var onNoteEvent: (@Sendable (NoteEvent) -> Void)?
    var onStatusTextChange: (@Sendable (String) -> Void)?

    private let logger = Logger(subsystem: "com.chiimagnus.LonelyPianist", category: "CoreMIDI-AVP")
    private let refreshScheduler = DebouncedActionScheduler(queue: .main, debounceSec: 0.2)

    private var clientRef: MIDIClientRef = 0
    private var inputPortRef: MIDIPortRef = 0
    private var connectedSources: [MIDIEndpointRef] = []
    private var isRunning = false
    private var didLogNonNoteMessage = false

    func start() throws {
        guard !isRunning else { return }

        try createClientIfNeeded()
        try createInputPortIfNeeded()
        try refreshSources()

        isRunning = true
        onStatusTextChange?("listening")
    }

    func stop() {
        isRunning = false
        refreshScheduler.cancel()

        disconnectAllSources()

        if inputPortRef != 0 {
            MIDIPortDispose(inputPortRef)
            inputPortRef = 0
        }

        if clientRef != 0 {
            MIDIClientDispose(clientRef)
            clientRef = 0
        }

        onStatusTextChange?("stopped")
    }

    func refreshSources() throws {
        guard inputPortRef != 0 else {
            onStatusTextChange?("MIDI input port is unavailable")
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

        let sourceNames = connectedSources.map(endpointName)
        onSourceNamesChange?(sourceNames)

        if connectedSources.isEmpty, let failedStatus {
            onStatusTextChange?("No MIDI source connected (status: \(failedStatus))")
            throw MIDIDebugInputServiceError.sourceRefresh(failedStatus)
        }

        onStatusTextChange?("sources: \(connectedSources.count)")
    }

    private func createClientIfNeeded() throws {
        guard clientRef == 0 else { return }

        let status = MIDIClientCreateWithBlock(
            "LonelyPianistAVPMIDIClient" as CFString,
            &clientRef
        ) { [weak self] message in
            let notification = message.pointee
            Task { @MainActor [weak self] in
                self?.handleMIDINotification(notification)
            }
        }

        guard status == noErr else {
            onStatusTextChange?("Create MIDI client failed: \(status)")
            throw MIDIDebugInputServiceError.clientCreate(status)
        }
    }

    private func createInputPortIfNeeded() throws {
        guard inputPortRef == 0 else { return }

        let status = MIDIInputPortCreateWithProtocol(
            clientRef,
            "LonelyPianistAVPMIDIInput" as CFString,
            MIDIProtocolID._1_0,
            &inputPortRef
        ) { [weak self] eventList, _ in
            Task { @MainActor [weak self] in
                self?.handleEventList(eventList)
            }
        }

        guard status == noErr else {
            onStatusTextChange?("Create MIDI input port failed: \(status)")
            throw MIDIDebugInputServiceError.portCreate(status)
        }
    }

    private func handleMIDINotification(_ notification: MIDINotification) {
        switch notification.messageID {
            case .msgObjectAdded, .msgObjectRemoved, .msgSetupChanged:
                scheduleRefreshSources()
            default:
                return
        }
    }

    private func scheduleRefreshSources() {
        guard isRunning else { return }
        refreshScheduler.schedule { [weak self] in
            guard let self else { return }
            guard self.isRunning, self.inputPortRef != 0 else { return }

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
                guard status == .noteOn || status == .noteOff else {
                    logNonNoteMessageOnce("MIDI data received, waiting for note on/off")
                    return
                }

                let channel = Int(message.channelVoice1.channel) + 1
                let note = Int(message.channelVoice1.note.number)
                let velocity = Int(message.channelVoice1.note.velocity)

                emitNoteEvent(
                    status == .noteOn && velocity > 0 ? .noteOn(note: note, velocity: velocity) : .noteOff(note: note, velocity: velocity),
                    channel: channel
                )

            case .channelVoice2:
                let status = message.channelVoice2.status
                guard status == .noteOn || status == .noteOff else {
                    logNonNoteMessageOnce("MIDI 2.0 data received, waiting for note on/off")
                    return
                }

                let channel = Int(message.channelVoice2.channel) + 1
                let note = Int(message.channelVoice2.note.number)
                let velocity16 = Int(message.channelVoice2.note.velocity)
                let velocity = Int((Double(velocity16) / 65535.0) * 127.0)

                emitNoteEvent(
                    status == .noteOn && velocity16 > 0 ? .noteOn(note: note, velocity: velocity) : .noteOff(note: note, velocity: velocity),
                    channel: channel
                )

            default:
                break
        }
    }

    private func logNonNoteMessageOnce(_ message: String) {
        guard !didLogNonNoteMessage else { return }
        didLogNonNoteMessage = true
        logger.info("\(message, privacy: .public)")
    }

    private func emitNoteEvent(_ kind: NoteEvent.Kind, channel: Int) {
        let clampedChannel = max(1, channel)
        let event = NoteEvent(kind: kind, channel: clampedChannel, timestamp: Date())
        onNoteEvent?(event)
    }
}

private func midiEventVisitor(
    context: UnsafeMutableRawPointer?,
    timeStamp: MIDITimeStamp,
    message: MIDIUniversalMessage
) {
    guard let context else { return }
    let service = Unmanaged<CoreMIDIDebugInputService>.fromOpaque(context).takeUnretainedValue()
    service.handleUniversalMessage(message, timeStamp: timeStamp)
}
