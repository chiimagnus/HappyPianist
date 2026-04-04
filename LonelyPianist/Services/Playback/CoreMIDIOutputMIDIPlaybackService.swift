import Foundation
import OSLog

enum CoreMIDIPlaybackError: LocalizedError {
    case destinationNotSelected

    var errorDescription: String? {
        switch self {
        case .destinationNotSelected:
            return "No MIDI destination selected."
        }
    }
}

@MainActor
final class CoreMIDIOutputMIDIPlaybackService: MIDIPlaybackServiceProtocol {
    private enum EventType {
        case noteOn(velocity: Int)
        case noteOff
    }

    private struct ScheduledEvent {
        let time: TimeInterval
        let note: Int
        let channel: Int
        let type: EventType
    }

    private struct ActiveNoteKey: Hashable {
        let note: UInt8
        let channel: UInt8
    }

    private let logger = Logger(subsystem: "com.chiimagnus.LonelyPianist", category: "CoreMIDIPlayback")
    private let outputService: MIDIOutputServiceProtocol
    private var playbackTask: Task<Void, Never>?
    private var activeNotes: Set<ActiveNoteKey> = []

    var destinationUniqueID: Int32?
    var onPlaybackFinished: (@Sendable () -> Void)?
    private(set) var isPlaying = false

    init(outputService: MIDIOutputServiceProtocol) {
        self.outputService = outputService
    }

    func play(take: RecordingTake) throws {
        try play(take: take, fromOffsetSec: 0)
    }

    func play(take: RecordingTake, fromOffsetSec offsetSec: TimeInterval) throws {
        stop()

        guard let destinationUniqueID else {
            throw CoreMIDIPlaybackError.destinationNotSelected
        }

        guard !take.notes.isEmpty else {
            onPlaybackFinished?()
            return
        }

        let events = makeEvents(from: take.notes, fromOffsetSec: offsetSec)
        isPlaying = true

        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.performPlayback(events: events, destinationUniqueID: destinationUniqueID)
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        stopAllActiveNotes()
        isPlaying = false
    }

    private func performPlayback(events: [ScheduledEvent], destinationUniqueID: Int32) async {
        let playbackStartedAt = Date()

        for event in events {
            let elapsed = Date().timeIntervalSince(playbackStartedAt)
            let delta = max(0, event.time - elapsed)
            if delta > 0 {
                let ns = UInt64(delta * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }

            guard !Task.isCancelled else { return }

            do {
                try apply(event: event, destinationUniqueID: destinationUniqueID)
            } catch {
                logger.error("Playback apply failed: \(error.localizedDescription, privacy: .public)")
                break
            }
        }

        stopAllActiveNotes()
        guard !Task.isCancelled else { return }

        isPlaying = false
        playbackTask = nil
        onPlaybackFinished?()
    }

    private func apply(event: ScheduledEvent, destinationUniqueID: Int32) throws {
        let note = UInt8(max(0, min(127, event.note)))
        let channel = UInt8(max(1, min(16, event.channel)))
        let key = ActiveNoteKey(note: note, channel: channel)

        switch event.type {
        case .noteOn(let velocity):
            let clampedVelocity = UInt8(max(1, min(127, velocity)))
            try outputService.sendNoteOn(
                note: note,
                velocity: clampedVelocity,
                channel: channel,
                destinationID: destinationUniqueID
            )
            activeNotes.insert(key)

        case .noteOff:
            try outputService.sendNoteOff(
                note: note,
                channel: channel,
                destinationID: destinationUniqueID
            )
            activeNotes.remove(key)
        }
    }

    private func stopAllActiveNotes() {
        guard let destinationUniqueID else {
            activeNotes.removeAll(keepingCapacity: false)
            return
        }

        for key in activeNotes {
            try? outputService.sendNoteOff(
                note: key.note,
                channel: key.channel,
                destinationID: destinationUniqueID
            )
        }
        activeNotes.removeAll(keepingCapacity: false)
    }

    private func makeEvents(from notes: [RecordedNote], fromOffsetSec offsetSec: TimeInterval) -> [ScheduledEvent] {
        var events: [ScheduledEvent] = []
        events.reserveCapacity(notes.count * 2)

        let offset = max(0, offsetSec)

        for note in notes {
            let startTime = max(0, note.startOffsetSec)
            let duration = max(0.01, note.durationSec)
            let endTime = startTime + duration

            guard endTime > offset else { continue }

            let adjustedStart: TimeInterval
            let adjustedEnd: TimeInterval

            if startTime >= offset {
                adjustedStart = startTime - offset
                adjustedEnd = endTime - offset
            } else {
                adjustedStart = 0
                adjustedEnd = endTime - offset
            }

            events.append(
                ScheduledEvent(
                    time: adjustedStart,
                    note: note.note,
                    channel: note.channel,
                    type: .noteOn(velocity: note.velocity)
                )
            )
            events.append(
                ScheduledEvent(
                    time: adjustedEnd,
                    note: note.note,
                    channel: note.channel,
                    type: .noteOff
                )
            )
        }

        return events.sorted { lhs, rhs in
            if lhs.time != rhs.time {
                return lhs.time < rhs.time
            }

            switch (lhs.type, rhs.type) {
            case (.noteOff, .noteOn):
                return true
            case (.noteOn, .noteOff):
                return false
            default:
                return lhs.note < rhs.note
            }
        }
    }
}

