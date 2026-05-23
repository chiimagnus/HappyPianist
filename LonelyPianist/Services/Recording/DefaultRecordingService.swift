import Foundation

final class DefaultRecordingService: RecordingServiceProtocol {
    private struct NoteKey: Hashable {
        let note: Int
        let channel: Int
    }

    private struct OpenNote {
        let id: UUID
        let startedAt: Date
        let velocity: Int
    }

    private let clock: ClockProtocol
    private var openNotes: [NoteKey: OpenNote] = [:]
    private var recordedNotes: [RecordedNote] = []

    private(set) var isRecording = false
    private(set) var startedAt: Date?

    init(clock: ClockProtocol) {
        self.clock = clock
    }

    func startRecording(at date: Date) {
        startedAt = date
        isRecording = true
        openNotes.removeAll(keepingCapacity: false)
        recordedNotes.removeAll(keepingCapacity: false)
    }

    func append(event: MIDIEvent) {
        guard isRecording, let startedAt else { return }

        let eventTimestamp = event.timestamp < startedAt ? clock.now() : event.timestamp
        let channel = max(1, event.channel)

        switch event.type {
        case let .noteOn(note, velocity):
            let clampedNote = max(0, min(127, note))
            let clampedVelocity = max(0, min(127, velocity))
            let key = NoteKey(note: clampedNote, channel: channel)
            if let openNote = openNotes[key] {
                appendRecordedNote(
                    id: openNote.id,
                    note: clampedNote,
                    velocity: openNote.velocity,
                    channel: channel,
                    startAt: openNote.startedAt,
                    endAt: eventTimestamp,
                    recordingStartedAt: startedAt
                )
            }
            openNotes[key] = OpenNote(id: UUID(), startedAt: eventTimestamp, velocity: clampedVelocity)

        case let .noteOff(note, _):
            let clampedNote = max(0, min(127, note))
            let key = NoteKey(note: clampedNote, channel: channel)
            guard let openNote = openNotes.removeValue(forKey: key) else { return }
            appendRecordedNote(
                id: openNote.id,
                note: clampedNote,
                velocity: openNote.velocity,
                channel: channel,
                startAt: openNote.startedAt,
                endAt: eventTimestamp,
                recordingStartedAt: startedAt
            )

        case .controlChange:
            return
        }
    }

    func stopRecording(at date: Date, takeID: UUID, name: String) -> RecordingTake? {
        guard isRecording, let startedAt else { return nil }
        let stopAt = date < startedAt ? clock.now() : date

        for (key, openNote) in openNotes {
            appendRecordedNote(
                id: openNote.id,
                note: key.note,
                velocity: openNote.velocity,
                channel: key.channel,
                startAt: openNote.startedAt,
                endAt: stopAt,
                recordingStartedAt: startedAt
            )
        }

        let sanitizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let takeName = sanitizedName.isEmpty ? "Take \(formatted(date: stopAt))" : sanitizedName
        let duration = max(0, stopAt.timeIntervalSince(startedAt))
        let notes = recordedNotes.sorted { lhs, rhs in
            if lhs.startOffsetSec != rhs.startOffsetSec {
                return lhs.startOffsetSec < rhs.startOffsetSec
            }
            return lhs.note < rhs.note
        }

        let take = RecordingTake(
            id: takeID,
            name: takeName,
            createdAt: startedAt,
            updatedAt: stopAt,
            durationSec: duration,
            notes: notes
        )

        cancelRecording()
        return take
    }

    func makeLivePreview(at date: Date, takeID: UUID, name: String) -> RecordingTake? {
        guard isRecording, let startedAt else { return nil }
        let now = date < startedAt ? clock.now() : date

        var notes = recordedNotes
        notes.reserveCapacity(recordedNotes.count + openNotes.count)

        for (key, openNote) in openNotes {
            let startOffset = max(0, openNote.startedAt.timeIntervalSince(startedAt))
            let duration = max(0.01, now.timeIntervalSince(openNote.startedAt))
            notes.append(
                RecordedNote(
                    id: openNote.id,
                    note: key.note,
                    velocity: openNote.velocity,
                    channel: key.channel,
                    startOffsetSec: startOffset,
                    durationSec: duration
                )
            )
        }

        notes.sort { lhs, rhs in
            if lhs.startOffsetSec != rhs.startOffsetSec {
                return lhs.startOffsetSec < rhs.startOffsetSec
            }
            return lhs.note < rhs.note
        }

        let sanitizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let takeName = sanitizedName.isEmpty ? "Take \(formatted(date: now))" : sanitizedName
        let duration = max(0, now.timeIntervalSince(startedAt))

        return RecordingTake(
            id: takeID,
            name: takeName,
            createdAt: startedAt,
            updatedAt: now,
            durationSec: duration,
            notes: notes
        )
    }

    func cancelRecording() {
        isRecording = false
        startedAt = nil
        openNotes.removeAll(keepingCapacity: false)
        recordedNotes.removeAll(keepingCapacity: false)
    }

    private func appendRecordedNote(
        id: UUID,
        note: Int,
        velocity: Int,
        channel: Int,
        startAt: Date,
        endAt: Date,
        recordingStartedAt: Date
    ) {
        let startOffset = max(0, startAt.timeIntervalSince(recordingStartedAt))
        let duration = max(0.01, endAt.timeIntervalSince(startAt))

        recordedNotes.append(
            RecordedNote(
                id: id,
                note: note,
                velocity: velocity,
                channel: channel,
                startOffsetSec: startOffset,
                durationSec: duration
            )
        )
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
