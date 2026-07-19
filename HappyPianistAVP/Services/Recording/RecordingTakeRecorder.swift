import Foundation

struct RecordingTakeRecorder {
    private struct NoteRoute: Hashable {
        let sourceKind: String?
        let sourceID: String
        let group: Int?
        let channel: Int?
        let midi: Int
    }

    private struct OpenNoteKey: Hashable {
        let route: NoteRoute
        let eventID: UUID
    }

    struct OpenNote: Equatable {
        let startTime: TimeInterval
        let observation: PerformanceObservation?
    }

    private(set) var isRecording = false
    private var takeStart: TimeInterval = 0
    private var openNotes: [OpenNoteKey: OpenNote] = [:]
    private var events: [RecordingTakeEvent] = []
    private var metadata = RecordingTakeMetadata.unattributed

    init() {}

    mutating func start(
        now: TimeInterval,
        metadata: RecordingTakeMetadata = .unattributed
    ) {
        reset()
        isRecording = true
        takeStart = now
        self.metadata = metadata
    }

    mutating func stop(now: TimeInterval, createdAt: Date = .now) -> RecordingTake {
        let relativeNow = max(0, now - takeStart)

        for (key, open) in openNotes {
            let endTime = max(relativeNow, open.startTime)
            events.append(
                RecordingTakeEvent(
                    time: endTime,
                    kind: .noteOff(midi: key.route.midi),
                    observation: synthesizedNoteOff(
                        midi: key.route.midi,
                        from: open.observation,
                        hostSeconds: now
                    )
                )
            )
        }
        openNotes.removeAll(keepingCapacity: true)

        isRecording = false

        let sortedEvents = events.sorted { $0.time < $1.time }
        let name = "Take \(formattedDate(createdAt))"
        return RecordingTake(name: name, createdAt: createdAt, metadata: metadata, events: sortedEvents)
    }

    mutating func recordNoteOn(
        note: Int,
        velocity: Int,
        now: TimeInterval,
        observation: PerformanceObservation? = nil
    ) {
        guard isRecording else { return }
        let relativeTime = max(0, now - takeStart)
        let clampedNote = max(0, min(127, note))
        let clampedVelocity = max(0, min(127, velocity))
        let route = noteRoute(note: clampedNote, observation: observation)

        for key in openNotes.keys.filter({ $0.route == route }) {
            guard let existing = openNotes.removeValue(forKey: key) else { continue }
            let endTime = max(relativeTime, existing.startTime)
            events.append(
                RecordingTakeEvent(
                    time: endTime,
                    kind: .noteOff(midi: clampedNote),
                    observation: synthesizedNoteOff(
                        midi: clampedNote,
                        from: observation ?? existing.observation,
                        hostSeconds: now
                    )
                )
            )
        }

        let key = OpenNoteKey(route: route, eventID: observation?.id ?? UUID())
        openNotes[key] = OpenNote(
            startTime: relativeTime,
            observation: observation
        )
        append(
            time: relativeTime,
            kind: .noteOn(midi: clampedNote, velocity: clampedVelocity),
            observation: observation
        )
    }

    mutating func recordNoteOff(
        note: Int,
        now: TimeInterval,
        observation: PerformanceObservation? = nil
    ) {
        guard isRecording else { return }
        let clampedNote = max(0, min(127, note))
        let route = noteRoute(note: clampedNote, observation: observation)
        guard let key = openNotes
            .filter({ $0.key.route == route })
            .min(by: { $0.value.startTime < $1.value.startTime })?
            .key,
            let open = openNotes.removeValue(forKey: key)
        else { return }
        let relativeTime = max(0, now - takeStart)
        let endTime = max(relativeTime, open.startTime)
        append(
            time: endTime,
            kind: .noteOff(midi: clampedNote),
            observation: observation
        )
    }

    mutating func closeAllOpenNotes(
        now: TimeInterval,
        matching observation: PerformanceObservation? = nil
    ) {
        guard isRecording else { return }
        let relativeTime = max(0, now - takeStart)
        let keys = openNotes.keys.filter { key in
            guard let observation else { return true }
            return key.route.sourceKind == observation.source.kind.rawValue
                && key.route.sourceID == observation.source.id
                && key.route.group == observation.group
                && key.route.channel == observation.channel
        }
        for key in keys {
            guard let open = openNotes.removeValue(forKey: key) else { continue }
            events.append(
                RecordingTakeEvent(
                    time: max(relativeTime, open.startTime),
                    kind: .noteOff(midi: key.route.midi),
                    observation: synthesizedNoteOff(
                        midi: key.route.midi,
                        from: observation ?? open.observation,
                        hostSeconds: now
                    )
                )
            )
        }
    }

    mutating func recordControlChange(
        controller: Int,
        value: Int,
        now: TimeInterval,
        observation: PerformanceObservation? = nil
    ) {
        guard isRecording else { return }
        let relativeTime = max(0, now - takeStart)
        let clampedController = max(0, min(127, controller))
        let clampedValue = max(0, min(127, value))
        append(
            time: relativeTime,
            kind: .controlChange(controller: clampedController, value: clampedValue),
            observation: observation
        )
    }

    mutating func recordPitchBend(
        value: Int,
        now: TimeInterval,
        observation: PerformanceObservation? = nil
    ) {
        guard isRecording else { return }
        let relativeTime = max(0, now - takeStart)
        let clampedValue = max(0, min(16383, value))
        append(
            time: relativeTime,
            kind: .pitchBend(value: clampedValue),
            observation: observation
        )
    }

    mutating func recordProgramChange(
        program: Int,
        now: TimeInterval,
        observation: PerformanceObservation? = nil
    ) {
        guard isRecording else { return }
        let relativeTime = max(0, now - takeStart)
        let clampedProgram = max(0, min(127, program))
        append(
            time: relativeTime,
            kind: .programChange(program: clampedProgram),
            observation: observation
        )
    }

    mutating func recordChannelPressure(
        value: Int,
        now: TimeInterval,
        observation: PerformanceObservation? = nil
    ) {
        guard isRecording else { return }
        let relativeTime = max(0, now - takeStart)
        let clampedValue = max(0, min(127, value))
        append(
            time: relativeTime,
            kind: .channelPressure(value: clampedValue),
            observation: observation
        )
    }

    mutating func recordPolyPressure(
        note: Int,
        value: Int,
        now: TimeInterval,
        observation: PerformanceObservation? = nil
    ) {
        guard isRecording else { return }
        let relativeTime = max(0, now - takeStart)
        let clampedNote = max(0, min(127, note))
        let clampedValue = max(0, min(127, value))
        append(
            time: relativeTime,
            kind: .polyPressure(midi: clampedNote, value: clampedValue),
            observation: observation
        )
    }

    private mutating func reset() {
        openNotes.removeAll(keepingCapacity: true)
        events.removeAll(keepingCapacity: true)
        takeStart = 0
        metadata = .unattributed
    }

    private func noteRoute(
        note: Int,
        observation: PerformanceObservation?
    ) -> NoteRoute {
        NoteRoute(
            sourceKind: observation?.source.kind.rawValue,
            sourceID: observation?.source.id ?? "unattributed-recording",
            group: observation?.group,
            channel: observation?.channel,
            midi: note
        )
    }

    private mutating func append(
        time: TimeInterval,
        kind: RecordingTakeEvent.Kind,
        observation: PerformanceObservation?
    ) {
        incorporateMetadata(from: observation)
        events.append(RecordingTakeEvent(
            time: time,
            kind: kind,
            observation: observation
        ))
    }

    private mutating func incorporateMetadata(from observation: PerformanceObservation?) {
        guard let observation else { return }
        let descriptor = RecordingInputSourceDescriptor(
            kind: observation.source.kind,
            id: observation.source.id,
            capabilities: observation.source.capabilities
        )
        let attributedSources = metadata.inputSources.filter { $0.kind != nil }
        let sources = attributedSources.contains(where: {
            $0.kind == descriptor.kind && $0.id == descriptor.id
        }) ? attributedSources : attributedSources + [descriptor]
        let mapping = metadata.clockMapping ?? observation.timing.mapping
        metadata = RecordingTakeMetadata(
            provenance: .recorded,
            scoreIdentity: metadata.scoreIdentity,
            inputSources: sources,
            clockMapping: mapping,
            latencyCorrectionSeconds: metadata.latencyCorrectionSeconds
                ?? mapping?.estimatedLatencySeconds,
            calibrationVersion: metadata.calibrationVersion
                ?? observation.calibrationReference
        )
    }

    private func synthesizedNoteOff(
        midi: Int,
        from observation: PerformanceObservation?,
        hostSeconds: TimeInterval
    ) -> PerformanceObservation? {
        guard let observation else { return nil }
        let host = PerformanceMonotonicInstant(seconds: hostSeconds)
        return PerformanceObservation(
            source: observation.source,
            timing: PerformanceClockReading(
                host: host,
                source: nil,
                correctedHost: host,
                mapping: observation.timing.mapping,
                provenance: observation.timing.mapping?.provenance ?? .hostOnly
            ),
            event: .noteOff(note: midi, releaseVelocity: nil),
            channel: observation.channel,
            group: observation.group,
            calibrationReference: observation.calibrationReference
        )
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
