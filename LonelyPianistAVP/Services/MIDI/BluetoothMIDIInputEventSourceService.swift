import CoreMIDI
import Foundation
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

final class BluetoothMIDIInputEventSourceService: PracticeInputEventSourceProtocol {
    var events: AsyncStream<PracticeInputEvent> {
        eventsStream
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP", category: "BluetoothMIDI-Events")
    private let refreshScheduler = DebouncedActionScheduler(queue: .main, debounceSec: 0.2)

    private var clientRef: MIDIClientRef = 0
    private var inputPortRef: MIDIPortRef = 0
    private var connectedSources: [MIDIEndpointRef] = []
    private var isRunning = false

    private let eventsStream: AsyncStream<PracticeInputEvent>
    private let eventsContinuation: AsyncStream<PracticeInputEvent>.Continuation

    init() {
        var continuation: AsyncStream<PracticeInputEvent>.Continuation?
        eventsStream = AsyncStream { continuation = $0 }
        eventsContinuation = continuation!
    }

    func start() throws {
        guard !isRunning else { return }

        try createClientIfNeeded()
        try createInputPortIfNeeded()

        isRunning = true
        try refreshSources()
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
    }

    func refreshSources() throws {
        guard inputPortRef != 0 else { return }

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

        if connectedSources.isEmpty, let failedStatus {
            throw BluetoothMIDIInputEventSourceServiceError.sourceRefresh(failedStatus)
        }
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
    }

    private func handleEventList(_ eventList: UnsafePointer<MIDIEventList>) {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        MIDIEventListForEachEvent(eventList, midiEventVisitor, context)
    }

    fileprivate func handleUniversalMessage(
        _ message: MIDIUniversalMessage,
        timeStamp _: MIDITimeStamp
    ) {
        let receivedAt = Date()
        let receivedAtUptimeSeconds = ProcessInfo.processInfo.systemUptime

        switch message.type {
        case .channelVoice1:
            let voice = message.channelVoice1
            let channel = Int(voice.channel) + 1

            switch voice.status {
            case .noteOn:
                let note = Int(voice.note.number)
                let velocity = Int(voice.note.velocity)
                let kind: PracticeInputEvent.Kind = velocity > 0 ? .noteOn(note: note, velocity: velocity) : .noteOff(note: note, velocity: 0)
                eventsContinuation.yield(PracticeInputEvent(kind: kind, channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            case .noteOff:
                let note = Int(voice.note.number)
                let velocity = Int(voice.note.velocity)
                eventsContinuation.yield(PracticeInputEvent(kind: .noteOff(note: note, velocity: velocity), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            case .controlChange:
                let controller = Int(voice.controlChange.index)
                let value = Int(voice.controlChange.data)
                eventsContinuation.yield(PracticeInputEvent(kind: .controlChange(controller: controller, value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            case .programChange:
                let program = Int(voice.program)
                eventsContinuation.yield(PracticeInputEvent(kind: .programChange(program: program), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            case .channelPressure:
                let value = Int(voice.channelPressure)
                eventsContinuation.yield(PracticeInputEvent(kind: .channelPressure(value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            case .polyPressure:
                let note = Int(voice.polyPressure.noteNumber)
                let value = Int(voice.polyPressure.pressure)
                eventsContinuation.yield(PracticeInputEvent(kind: .polyPressure(note: note, value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            case .pitchBend:
                let value = Int(voice.pitchBend)
                eventsContinuation.yield(PracticeInputEvent(kind: .pitchBend(value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            default:
                break
            }

        case .channelVoice2:
            let voice = message.channelVoice2
            let channel = Int(voice.channel) + 1

            switch voice.status {
            case .noteOn:
                let note = Int(voice.note.number)
                let velocity16 = voice.note.velocity
                let velocity = scaleMIDI2Value16To127(velocity16)
                let kind: PracticeInputEvent.Kind = velocity16 > 0 ? .noteOn(note: note, velocity: velocity) : .noteOff(note: note, velocity: 0)
                eventsContinuation.yield(PracticeInputEvent(kind: kind, channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            case .noteOff:
                let note = Int(voice.note.number)
                let velocity16 = voice.note.velocity
                let velocity = scaleMIDI2Value16To127(velocity16)
                eventsContinuation.yield(PracticeInputEvent(kind: .noteOff(note: note, velocity: velocity), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            case .controlChange:
                let controller = Int(voice.controlChange.index)
                let value = scaleMIDI2Value32To127(UInt32(voice.controlChange.data))
                eventsContinuation.yield(PracticeInputEvent(kind: .controlChange(controller: controller, value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            case .programChange:
                let program = Int(voice.programChange.program)
                eventsContinuation.yield(PracticeInputEvent(kind: .programChange(program: program), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            case .channelPressure:
                let value = scaleMIDI2Value32To127(UInt32(voice.channelPressure.data))
                eventsContinuation.yield(PracticeInputEvent(kind: .channelPressure(value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            case .polyPressure:
                let note = Int(voice.polyPressure.noteNumber)
                let value = scaleMIDI2Value32To127(UInt32(voice.polyPressure.pressure))
                eventsContinuation.yield(PracticeInputEvent(kind: .polyPressure(note: note, value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            case .pitchBend:
                let value = scaleMIDI2PitchBendTo14Bit(UInt32(voice.pitchBend.data))
                eventsContinuation.yield(PracticeInputEvent(kind: .pitchBend(value: value), channel: channel, receivedAt: receivedAt, receivedAtUptimeSeconds: receivedAtUptimeSeconds))

            default:
                break
            }

        default:
            break
        }
    }

    private func scaleMIDI2Value16To127(_ value: UInt16) -> Int {
        Int((Double(value) / 65_535.0) * 127.0)
    }

    private func scaleMIDI2Value32To127(_ value: UInt32) -> Int {
        Int((Double(value) / Double(UInt32.max)) * 127.0)
    }

    private func scaleMIDI2PitchBendTo14Bit(_ value: UInt32) -> Int {
        Int((Double(value) / Double(UInt32.max)) * 16_383.0)
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
