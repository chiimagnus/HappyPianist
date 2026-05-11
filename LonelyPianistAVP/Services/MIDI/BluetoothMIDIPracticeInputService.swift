import CoreMIDI
import Foundation
import OSLog

protocol BluetoothMIDIPracticeInputServiceProtocol: AnyObject {
    var events: AsyncStream<DetectedNoteEvent> { get }

    func start(generation: Int) throws -> Int
    func updateGeneration(_ generation: Int)
    func stop()
}

enum BluetoothMIDIPracticeInputServiceError: LocalizedError {
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

final class BluetoothMIDIPracticeInputService: BluetoothMIDIPracticeInputServiceProtocol {
    var events: AsyncStream<DetectedNoteEvent> {
        eventsStream
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP", category: "Step3BluetoothMIDI")
    private let refreshScheduler = DebouncedActionScheduler(queue: .main, debounceSec: 0.2)

    private var clientRef: MIDIClientRef = 0
    private var inputPortRef: MIDIPortRef = 0
    private var connectedSources: [MIDIEndpointRef] = []
    private var isRunning = false
    private var currentGeneration = 0

    private let eventsStream: AsyncStream<DetectedNoteEvent>
    private let eventsContinuation: AsyncStream<DetectedNoteEvent>.Continuation

    init() {
        var continuation: AsyncStream<DetectedNoteEvent>.Continuation?
        eventsStream = AsyncStream { continuation = $0 }
        eventsContinuation = continuation!
    }

    func start(generation: Int) throws -> Int {
        if !isRunning {
            try createClientIfNeeded()
            try createInputPortIfNeeded()
            isRunning = true
        }

        currentGeneration = generation
        do {
            try refreshSources()
        } catch {
            isRunning = false
            throw error
        }

        return connectedSources.count
    }

    func updateGeneration(_ generation: Int) {
        currentGeneration = generation
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
            throw BluetoothMIDIPracticeInputServiceError.sourceRefresh(failedStatus)
        }
    }

    private func createClientIfNeeded() throws {
        guard clientRef == 0 else { return }

        let status = MIDIClientCreateWithBlock(
            "LonelyPianistAVPBluetoothMIDIClient" as CFString,
            &clientRef
        ) { [weak self] message in
            let notification = message.pointee
            Task { @MainActor [weak self] in
                self?.handleMIDINotification(notification)
            }
        }

        guard status == noErr else {
            throw BluetoothMIDIPracticeInputServiceError.clientCreate(status)
        }
    }

    private func createInputPortIfNeeded() throws {
        guard inputPortRef == 0 else { return }

        let status = MIDIInputPortCreateWithProtocol(
            clientRef,
            "LonelyPianistAVPBluetoothMIDIInput" as CFString,
            MIDIProtocolID._1_0,
            &inputPortRef
        ) { [weak self] eventList, _ in
            Task { @MainActor [weak self] in
                self?.handleEventList(eventList)
            }
        }

        guard status == noErr else {
            throw BluetoothMIDIPracticeInputServiceError.portCreate(status)
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
                guard status == .noteOn || status == .noteOff else { return }

                let note = Int(message.channelVoice1.note.number)
                let velocity = Int(message.channelVoice1.note.velocity)
                emitIfNoteOn(isNoteOn: status == .noteOn, note: note, velocity: velocity)

            case .channelVoice2:
                let status = message.channelVoice2.status
                guard status == .noteOn || status == .noteOff else { return }

                let note = Int(message.channelVoice2.note.number)
                let velocity16 = Int(message.channelVoice2.note.velocity)
                let velocity = Int((Double(velocity16) / 65535.0) * 127.0)
                emitIfNoteOn(isNoteOn: status == .noteOn, note: note, velocity: velocity)

            default:
                break
        }
    }

    private func emitIfNoteOn(isNoteOn: Bool, note: Int, velocity: Int) {
        guard isNoteOn, velocity > 0 else { return }

        let event = DetectedNoteEvent(
            midiNote: max(0, min(127, note)),
            confidence: 1.0,
            onsetScore: 1.0,
            isOnset: true,
            timestamp: Date(),
            generation: currentGeneration,
            source: .bluetoothMIDI
        )
        eventsContinuation.yield(event)
    }
}

private func midiEventVisitor(
    context: UnsafeMutableRawPointer?,
    timeStamp: MIDITimeStamp,
    message: MIDIUniversalMessage
) {
    guard let context else { return }
    let service = Unmanaged<BluetoothMIDIPracticeInputService>.fromOpaque(context).takeUnretainedValue()
    service.handleUniversalMessage(message, timeStamp: timeStamp)
}
