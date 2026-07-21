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
    private var recordingGeneration: UInt64 = 0
    private var activeKeyContactIDsByMIDINote: [Int: Set<PianoKeyContactID>] = [:]

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

    func startRecordingIfPossible(
        canRecord: Bool,
        metadata: RecordingTakeMetadata = .unattributed
    ) {
        guard canRecord else { return }
        let now = nowUptimeSeconds()
        recordingGeneration &+= 1
        activeKeyContactIDsByMIDINote.removeAll(keepingCapacity: true)
        midiRecordingAdapter.beginRecording()
        takeRecorder.start(now: now, metadata: metadata)
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
        activeKeyContactIDsByMIDINote.removeAll(keepingCapacity: true)
        notifyStateChanged()

        guard take.events.isEmpty == false else { return }
        onTakeRecorded(take)
    }

    func recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: Bool,
        isVirtualPianoEnabled: Bool,
        observations: [PianoKeyContactObservation]
    ) {
        guard usesBluetoothMIDIInput == false else { return }
        guard isRecording else { return }
        let sourceKind: PerformanceObservation.Source.Kind = isVirtualPianoEnabled
            ? .virtualPianoContact
            : .realPianoContact

        for contact in observations {
            guard let note = contact.keyCandidate.exactMIDINote else { continue }
            let observation = performanceObservation(from: contact, sourceKind: sourceKind)
            switch contact.phase {
            case .started:
                guard let velocity = contact.resolvedVelocity else { continue }
                var activeContactIDs = activeKeyContactIDsByMIDINote[note, default: []]
                let shouldRecordNoteOn = activeContactIDs.isEmpty
                guard activeContactIDs.insert(contact.id).inserted else { continue }
                activeKeyContactIDsByMIDINote[note] = activeContactIDs
                guard shouldRecordNoteOn else { continue }
                takeRecorder.recordNoteOn(
                    note: note,
                    velocity: Int(velocity),
                    now: contact.timestamp.seconds,
                    observation: observation
                )
            case .ended:
                guard var activeContactIDs = activeKeyContactIDsByMIDINote[note],
                      activeContactIDs.remove(contact.id) != nil
                else { continue }
                guard activeContactIDs.isEmpty else {
                    activeKeyContactIDsByMIDINote[note] = activeContactIDs
                    continue
                }
                activeKeyContactIDsByMIDINote.removeValue(forKey: note)
                takeRecorder.recordNoteOff(
                    note: note,
                    now: contact.timestamp.seconds,
                    observation: observation
                )
            case .held:
                break
            }
        }
    }

    private func performanceObservation(
        from contact: PianoKeyContactObservation,
        sourceKind: PerformanceObservation.Source.Kind
    ) -> PerformanceObservation {
        let phase: PerformanceObservation.ContactPhase = switch contact.phase {
        case .started: .started
        case .held: .held
        case .ended: .ended
        }
        return PerformanceObservation(
            source: PerformanceObservation.Source(
                kind: sourceKind,
                id: sourceKind == .virtualPianoContact
                    ? "virtual-piano-key-contact"
                    : "real-piano-key-contact",
                generation: recordingGeneration,
                capabilities: .handContact
            ),
            timing: PerformanceClockReading(
                host: contact.timestamp,
                source: nil,
                correctedHost: contact.timestamp,
                mapping: nil,
                provenance: .hostOnly
            ),
            event: .contact(
                id: "\(contact.hand)-\(contact.finger)-\(contact.id.sequence)",
                keyCandidate: contact.keyCandidate.exactMIDINote,
                phase: phase
            ),
            hand: contact.hand.scoreHand,
            finger: Int(contact.finger.rawValue) + 1,
            confidence: Double(contact.confidence),
            calibrationReference: contact.calibrationID.uuidString
        )
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

private extension TrackedHandSide {
    var scoreHand: ScoreHand {
        switch self {
        case .left: .left
        case .right: .right
        }
    }
}
