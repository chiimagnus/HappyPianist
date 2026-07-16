import Foundation

@MainActor
final class MIDIRecordingState {
    struct State: Equatable {
        var isRecording: Bool
        var recordingStartDate: Date?
    }

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
        nowUptimeSeconds: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        nowDate: @escaping () -> Date = Date.init,
        onStateChanged: @escaping @MainActor (State) -> Void,
        onTakeRecorded: @escaping @MainActor (RecordingTake) -> Void,
        onMIDI1Event: (@MainActor (MIDI1InputEvent) -> Void)? = nil,
        onMIDI2Event: (@MainActor (MIDI2InputEvent) -> Void)? = nil
    ) {
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

    private func handleMIDI1TakeRecordingEvent(_ event: MIDI1InputEvent) {
        guard Task.isCancelled == false else { return }

        onMIDI1Event?(event)

        if isRecording {
            midiRecordingAdapter.record(event: event, into: &takeRecorder)
        }
    }

    private func handleMIDI2TakeRecordingEvent(_ event: MIDI2InputEvent) {
        guard Task.isCancelled == false else { return }

        onMIDI2Event?(event)

        if isRecording {
            midiRecordingAdapter.record(event: event, into: &takeRecorder)
        }
    }
}
