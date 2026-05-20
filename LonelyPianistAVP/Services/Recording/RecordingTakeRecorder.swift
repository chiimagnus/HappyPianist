import Foundation

struct RecordingTakeRecorder {
    struct OpenNote: Equatable {
        let startTime: TimeInterval
        let velocity: Int
    }

    private(set) var isRecording = false
    private var takeStart: TimeInterval = 0
    private var openNotes: [Int: OpenNote] = [:]
    private var events: [RecordingTakeEvent] = []

    init() {}

    mutating func start(now: TimeInterval) {
        reset()
        isRecording = true
        takeStart = now
    }

    mutating func stop(now: TimeInterval, createdAt: Date = .now) -> RecordingTake {
        let relativeNow = max(0, now - takeStart)

        for (midi, open) in openNotes {
            let endTime = max(relativeNow, open.startTime)
            events.append(
                RecordingTakeEvent(time: endTime, kind: .noteOff(midi: midi))
            )
        }
        openNotes.removeAll(keepingCapacity: true)

        isRecording = false

        let sortedEvents = events.sorted { $0.time < $1.time }
        let name = "Take \(formattedDate(createdAt))"
        return RecordingTake(name: name, createdAt: createdAt, events: sortedEvents)
    }

    mutating func recordNoteOn(note: Int, velocity: Int, now: TimeInterval) {
        guard isRecording else { return }
        let relativeTime = max(0, now - takeStart)
        let clampedNote = max(0, min(127, note))
        let clampedVelocity = max(0, min(127, velocity))

        if let existing = openNotes[clampedNote] {
            let endTime = max(relativeTime, existing.startTime)
            events.append(
                RecordingTakeEvent(time: endTime, kind: .noteOff(midi: clampedNote))
            )
        }

        openNotes[clampedNote] = OpenNote(startTime: relativeTime, velocity: clampedVelocity)
        events.append(
            RecordingTakeEvent(time: relativeTime, kind: .noteOn(midi: clampedNote, velocity: clampedVelocity))
        )
    }

    mutating func recordNoteOff(note: Int, now: TimeInterval) {
        guard isRecording else { return }
        let clampedNote = max(0, min(127, note))
        guard let open = openNotes.removeValue(forKey: clampedNote) else { return }
        let relativeTime = max(0, now - takeStart)
        let endTime = max(relativeTime, open.startTime)
        events.append(
            RecordingTakeEvent(time: endTime, kind: .noteOff(midi: clampedNote))
        )
    }

    mutating func recordControlChange(controller: Int, value: Int, now: TimeInterval) {
        guard isRecording else { return }
        let relativeTime = max(0, now - takeStart)
        let clampedController = max(0, min(127, controller))
        let clampedValue = max(0, min(127, value))
        events.append(
            RecordingTakeEvent(
                time: relativeTime,
                kind: .controlChange(controller: clampedController, value: clampedValue)
            )
        )
    }

    mutating func recordPitchBend(value: Int, now: TimeInterval) {
        guard isRecording else { return }
        let relativeTime = max(0, now - takeStart)
        let clampedValue = max(0, min(16383, value))
        events.append(
            RecordingTakeEvent(time: relativeTime, kind: .pitchBend(value: clampedValue))
        )
    }

    mutating func recordProgramChange(program: Int, now: TimeInterval) {
        guard isRecording else { return }
        let relativeTime = max(0, now - takeStart)
        let clampedProgram = max(0, min(127, program))
        events.append(
            RecordingTakeEvent(time: relativeTime, kind: .programChange(program: clampedProgram))
        )
    }

    mutating func recordChannelPressure(value: Int, now: TimeInterval) {
        guard isRecording else { return }
        let relativeTime = max(0, now - takeStart)
        let clampedValue = max(0, min(127, value))
        events.append(
            RecordingTakeEvent(time: relativeTime, kind: .channelPressure(value: clampedValue))
        )
    }

    mutating func recordPolyPressure(note: Int, value: Int, now: TimeInterval) {
        guard isRecording else { return }
        let relativeTime = max(0, now - takeStart)
        let clampedNote = max(0, min(127, note))
        let clampedValue = max(0, min(127, value))
        events.append(
            RecordingTakeEvent(time: relativeTime, kind: .polyPressure(midi: clampedNote, value: clampedValue))
        )
    }

    private mutating func reset() {
        openNotes.removeAll(keepingCapacity: true)
        events.removeAll(keepingCapacity: true)
        takeStart = 0
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
