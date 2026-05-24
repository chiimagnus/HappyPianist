import Foundation
import ImprovProtocol

/// A pure-logic phrase buffer which records user notes (note-on / note-off) into `ImprovDialogueNote`s.
///
/// This buffer intentionally does not decide *when* to flush; that belongs to `DuetTurnTakingCore`.
struct DuetPhraseBuffer: Sendable {
    struct OpenNote: Equatable, Sendable {
        let startTimestampSeconds: TimeInterval
        let velocity: Int
    }

    private var phraseStartTimestampSeconds: TimeInterval?
    private var openNotes: [Int: OpenNote] = [:]
    private var recordedNotes: [ImprovDialogueNote] = []

    init() {}

    var heldNotesCount: Int { openNotes.count }

    mutating func recordNoteOn(midi: Int, velocity: Int, timestampSeconds: TimeInterval) {
        if phraseStartTimestampSeconds == nil {
            phraseStartTimestampSeconds = timestampSeconds
        }

        if let existing = openNotes[midi] {
            let endTimestamp = max(timestampSeconds, existing.startTimestampSeconds)
            recordedNotes.append(
                ImprovDialogueNote(
                    note: midi,
                    velocity: existing.velocity,
                    time: existing.startTimestampSeconds,
                    duration: max(0.05, endTimestamp - existing.startTimestampSeconds)
                )
            )
        }

        openNotes[midi] = OpenNote(startTimestampSeconds: timestampSeconds, velocity: velocity)
    }

    mutating func recordNoteOff(midi: Int, timestampSeconds: TimeInterval) {
        guard let open = openNotes.removeValue(forKey: midi) else { return }
        let endTimestamp = max(timestampSeconds, open.startTimestampSeconds)
        recordedNotes.append(
            ImprovDialogueNote(
                note: midi,
                velocity: open.velocity,
                time: open.startTimestampSeconds,
                duration: max(0.05, endTimestamp - open.startTimestampSeconds)
            )
        )
    }

    mutating func flushPhrase(endTimestampSeconds: TimeInterval) -> [ImprovDialogueNote] {
        for (midi, open) in openNotes {
            let endTimestamp = max(endTimestampSeconds, open.startTimestampSeconds)
            recordedNotes.append(
                ImprovDialogueNote(
                    note: midi,
                    velocity: open.velocity,
                    time: open.startTimestampSeconds,
                    duration: max(0.05, endTimestamp - open.startTimestampSeconds)
                )
            )
        }
        openNotes.removeAll(keepingCapacity: true)

        guard recordedNotes.isEmpty == false else {
            phraseStartTimestampSeconds = nil
            return []
        }

        let base = phraseStartTimestampSeconds ?? (recordedNotes.map(\.time).min() ?? 0)
        phraseStartTimestampSeconds = nil

        let rebased = recordedNotes.map { note in
            ImprovDialogueNote(
                note: note.note,
                velocity: note.velocity,
                time: max(0, note.time - base),
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
        phraseStartTimestampSeconds = nil
        openNotes.removeAll()
        recordedNotes.removeAll()
    }
}

