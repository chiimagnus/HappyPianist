import Foundation

nonisolated struct PhraseRecorder {
    struct OpenNote: Equatable {
        let startTimestamp: TimeInterval
        let velocity: Int
    }

    private var openNotes: [Int: OpenNote] = [:]
    private var recordedNotes: [ImprovDialogueNote] = []

    init() {}

    mutating func recordNoteOn(midi: Int, velocity: Int, timestamp: TimeInterval) {
        if let existing = openNotes[midi] {
            let endTimestamp = max(timestamp, existing.startTimestamp)
            let duration = max(0.05, endTimestamp - existing.startTimestamp)
            recordedNotes.append(
                ImprovDialogueNote(note: midi, velocity: existing.velocity, time: existing.startTimestamp, duration: duration)
            )
        }

        openNotes[midi] = OpenNote(startTimestamp: timestamp, velocity: velocity)
    }

    mutating func recordNoteOff(midi: Int, timestamp: TimeInterval) {
        guard let open = openNotes.removeValue(forKey: midi) else { return }
        let endTimestamp = max(timestamp, open.startTimestamp)
        let duration = max(0.05, endTimestamp - open.startTimestamp)
        recordedNotes.append(
            ImprovDialogueNote(note: midi, velocity: open.velocity, time: open.startTimestamp, duration: duration)
        )
    }

    mutating func flushPhrase(endTimestamp: TimeInterval) -> [ImprovDialogueNote] {
        for (midi, open) in openNotes {
            let endTimestamp = max(endTimestamp, open.startTimestamp)
            let duration = max(0.05, endTimestamp - open.startTimestamp)
            recordedNotes.append(
                ImprovDialogueNote(note: midi, velocity: open.velocity, time: open.startTimestamp, duration: duration)
            )
        }
        openNotes.removeAll(keepingCapacity: true)

        guard recordedNotes.isEmpty == false else { return [] }

        let minTime = recordedNotes.map(\.time).min() ?? 0
        let rebased = recordedNotes.map { note in
            ImprovDialogueNote(
                note: note.note,
                velocity: note.velocity,
                time: max(0, note.time - minTime),
                duration: note.duration
            )
        }
        recordedNotes.removeAll(keepingCapacity: true)
        return rebased.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.note < rhs.note
        }
    }

    mutating func reset() {
        openNotes.removeAll()
        recordedNotes.removeAll()
    }
}

