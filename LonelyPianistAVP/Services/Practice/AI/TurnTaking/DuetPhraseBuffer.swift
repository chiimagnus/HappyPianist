import Foundation
import ImprovProtocol

/// A pure-logic phrase buffer which records user notes (note-on / note-off) into `ImprovDialogueNote`s.
///
/// This buffer intentionally does not decide *when* to flush; that belongs to `DuetTurnTakingCore`.
struct DuetPhraseBuffer: Sendable {
    struct FlushResult: Equatable, Sendable {
        /// Trimmed and rebased notes (A.I. Duet style: if duration > 10s keep last 15s and rebase).
        let trimmedNotes: [ImprovDialogueNote]

        /// Phrase duration before trimming/rebasing.
        let untrimmedEndTimeSeconds: TimeInterval

        /// Phrase duration after trimming.
        let endTimeSeconds: TimeInterval
    }

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

    mutating func flushPhrase(endTimestampSeconds: TimeInterval) -> FlushResult {
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
            return FlushResult(trimmedNotes: [], untrimmedEndTimeSeconds: 0, endTimeSeconds: 0)
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

        let sorted = rebased.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.note < rhs.note
        }

        let phraseEndTimeSeconds = sorted.map { $0.time + $0.duration }.max() ?? 0
        if phraseEndTimeSeconds <= 10 {
            return FlushResult(
                trimmedNotes: sorted,
                untrimmedEndTimeSeconds: phraseEndTimeSeconds,
                endTimeSeconds: phraseEndTimeSeconds
            )
        }

        let windowStartSeconds = max(0, phraseEndTimeSeconds - 15)
        let windowed = sorted.filter { $0.time >= windowStartSeconds }
        guard windowed.isEmpty == false else {
            return FlushResult(trimmedNotes: [], untrimmedEndTimeSeconds: phraseEndTimeSeconds, endTimeSeconds: 0)
        }

        let windowBase = windowStartSeconds
        let rebasedWindow = windowed.map { note in
            ImprovDialogueNote(
                note: note.note,
                velocity: note.velocity,
                time: max(0, note.time - windowBase),
                duration: note.duration
            )
        }.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.note < rhs.note
        }
        let rebasedEndTimeSeconds = rebasedWindow.map { $0.time + $0.duration }.max() ?? 0
        return FlushResult(
            trimmedNotes: rebasedWindow,
            untrimmedEndTimeSeconds: phraseEndTimeSeconds,
            endTimeSeconds: rebasedEndTimeSeconds
        )
    }

    mutating func reset() {
        phraseStartTimestampSeconds = nil
        openNotes.removeAll()
        recordedNotes.removeAll()
    }
}
