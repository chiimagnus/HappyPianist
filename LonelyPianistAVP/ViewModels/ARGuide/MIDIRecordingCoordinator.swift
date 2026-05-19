import Foundation
import os

@MainActor
final class MIDIRecordingCoordinator {
    struct State: Equatable {
        var isRecording: Bool
        var recordingStartDate: Date?
    }

    private let logger: Logger
    private let nowUptimeSeconds: () -> TimeInterval
    private let nowDate: () -> Date
    private let onStateChanged: @MainActor (State) -> Void
    private let onTakeRecorded: @MainActor (RecordingTake) -> Void
    private let onMIDI1Event: (@MainActor (MIDI1InputEvent) -> Void)?
    private let onMIDI2Event: (@MainActor (MIDI2InputEvent) -> Void)?

    private var midiRecordingAdapter = MIDIRecordingAdapter()
    private var takeRecorder = RecordingTakeRecorder()

    private var midi1Task: Task<Void, Never>?
    private var midi2Task: Task<Void, Never>?
    private var hasShutdown = false

    private var isRecording = false
    private var recordingStartDate: Date?

    init(
        logger: Logger,
        nowUptimeSeconds: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        nowDate: @escaping () -> Date = Date.init,
        onStateChanged: @escaping @MainActor (State) -> Void,
        onTakeRecorded: @escaping @MainActor (RecordingTake) -> Void,
        onMIDI1Event: (@MainActor (MIDI1InputEvent) -> Void)? = nil,
        onMIDI2Event: (@MainActor (MIDI2InputEvent) -> Void)? = nil
    ) {
        self.logger = logger
        self.nowUptimeSeconds = nowUptimeSeconds
        self.nowDate = nowDate
        self.onStateChanged = onStateChanged
        self.onTakeRecorded = onTakeRecorded
        self.onMIDI1Event = onMIDI1Event
        self.onMIDI2Event = onMIDI2Event
    }

    func shutdown() {
        guard hasShutdown == false else { return }
        hasShutdown = true
        stop()
    }

    func stop() {
        stopMIDISubscription()
        stopRecordingIfNeeded()
    }

    func refreshMIDISubscriptionIfNeeded(
        usesBluetoothMIDIInput: Bool,
        eventSource: PracticeInputEventSourceProtocol?
    ) {
        stopMIDISubscription()

        guard usesBluetoothMIDIInput else { return }
        guard let eventSource else { return }

        let midi1Stream = eventSource.midi1EventsStream()
        midi1Task = Task { [weak self] in
            for await event in midi1Stream {
                await MainActor.run {
                    self?.handleMIDI1TakeRecordingEvent(event)
                }
            }
        }

        let midi2Stream = eventSource.midi2EventsStream()
        midi2Task = Task { [weak self] in
            for await event in midi2Stream {
                await MainActor.run {
                    self?.handleMIDI2TakeRecordingEvent(event)
                }
            }
        }
    }

    func startRecordingIfPossible(canRecord: Bool) {
        guard canRecord else { return }
        let now = nowUptimeSeconds()
        takeRecorder.start(now: now)
        isRecording = true
        recordingStartDate = nowDate()
        notifyStateChanged()
    }

    func stopRecordingIfNeeded() {
        guard isRecording else { return }
        let now = nowUptimeSeconds()
        let createdAt = nowDate()
        let take = takeRecorder.stop(now: now, createdAt: createdAt)

        isRecording = false
        recordingStartDate = nil
        notifyStateChanged()

        guard take.events.isEmpty == false else { return }
        onTakeRecorded(take)
    }

    func recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: Bool,
        isVirtualPianoEnabled: Bool,
        keyContact: KeyContactResult,
        nowUptimeSeconds: TimeInterval
    ) {
        guard usesBluetoothMIDIInput == false else { return }
        guard isVirtualPianoEnabled == false else { return }
        guard isRecording else { return }

        for note in keyContact.started {
            takeRecorder.recordNoteOn(note: note, velocity: 90, now: nowUptimeSeconds)
        }
        for note in keyContact.ended {
            takeRecorder.recordNoteOff(note: note, now: nowUptimeSeconds)
        }
    }

    private func stopMIDISubscription() {
        midi1Task?.cancel()
        midi1Task = nil
        midi2Task?.cancel()
        midi2Task = nil
    }

    private func notifyStateChanged() {
        onStateChanged(State(isRecording: isRecording, recordingStartDate: recordingStartDate))
    }

    private func logMIDIPerNoteIfEnabled(_ message: String) {
        let config = MIDIDiagnosticsConfiguration.live()
        if config.isPerNoteInfoLoggingEnabled {
            logger.info("\(message, privacy: .public)")
            return
        }
        if config.isPerNoteDebugLoggingEnabled {
            logger.debug("\(message, privacy: .public)")
        }
    }

    private func handleMIDI1TakeRecordingEvent(_ event: MIDI1InputEvent) {
        guard Task.isCancelled == false else { return }

        onMIDI1Event?(event)

        if let id = event.debugEventID {
            switch event.kind {
            case let .noteOn(note, velocity):
                logMIDIPerNoteIfEnabled("recording saw midi1 id=\(id) src=\(describe(event.source)) noteOn=\(note) vel=\(velocity)")
            case let .noteOff(note, velocity):
                logMIDIPerNoteIfEnabled("recording saw midi1 id=\(id) src=\(describe(event.source)) noteOff=\(note) vel=\(velocity)")
            default:
                break
            }
        }

        if isRecording {
            midiRecordingAdapter.record(event: event, into: &takeRecorder)
        }
    }

    private func handleMIDI2TakeRecordingEvent(_ event: MIDI2InputEvent) {
        guard Task.isCancelled == false else { return }

        onMIDI2Event?(event)

        if let id = event.debugEventID {
            switch event.kind {
            case let .noteOn(note, velocity16):
                logMIDIPerNoteIfEnabled("recording saw midi2 id=\(id) src=\(describe(event.source)) noteOn=\(note) vel16=\(Int(velocity16))")
            case let .noteOff(note, velocity16):
                logMIDIPerNoteIfEnabled("recording saw midi2 id=\(id) src=\(describe(event.source)) noteOff=\(note) vel16=\(Int(velocity16))")
            default:
                break
            }
        }

        if isRecording {
            midiRecordingAdapter.record(event: event, into: &takeRecorder)
        }
    }

    private func describe(_ source: MIDI1InputEvent.Source) -> String {
        switch source.identifier {
        case let .endpointUniqueID(uniqueID):
            if let name = source.endpointName, name.isEmpty == false {
                return "uid=\(uniqueID)(\(name))"
            }
            return "uid=\(uniqueID)"
        case let .sourceIndex(index):
            if let name = source.endpointName, name.isEmpty == false {
                return "idx=\(index)(\(name))"
            }
            return "idx=\(index)"
        }
    }

    private func describe(_ source: MIDI2InputEvent.Source) -> String {
        switch source.identifier {
        case let .endpointUniqueID(uniqueID):
            if let name = source.endpointName, name.isEmpty == false {
                return "uid=\(uniqueID)(\(name))"
            }
            return "uid=\(uniqueID)"
        case let .sourceIndex(index):
            if let name = source.endpointName, name.isEmpty == false {
                return "idx=\(index)(\(name))"
            }
            return "idx=\(index)"
        }
    }
}
