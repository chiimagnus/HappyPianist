import AudioToolbox
import AVFAudio
import Foundation

enum MIDIPlaybackError: LocalizedError {
    case soundBankNotFound
    case engineStartFailed(Error)

    var errorDescription: String? {
        switch self {
            case .soundBankNotFound:
                "Piano sound bank is unavailable on this macOS installation."
            case let .engineStartFailed(error):
                "Audio engine failed to start: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class AVSamplerMIDIPlaybackService: MIDIPlaybackServiceProtocol {
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

    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var playbackTask: Task<Void, Never>?
    private var activeNotes: Set<ActiveNoteKey> = []
    private var didPrepareEngine = false

    var onPlaybackFinished: (@Sendable () -> Void)?
    private(set) var isPlaying = false

    init() {}

    func play(take: RecordingTake) throws {
        try play(take: take, fromOffsetSec: 0)
    }

    func play(take: RecordingTake, fromOffsetSec offsetSec: TimeInterval) throws {
        stop()

        try prepareEngineIfNeeded()

        guard !take.notes.isEmpty else {
            onPlaybackFinished?()
            return
        }

        let events = makeEvents(from: take.notes, fromOffsetSec: offsetSec)
        isPlaying = true

        playbackTask = Task { [weak self] in
            guard let self else { return }
            await performPlayback(events)
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        stopAllActiveNotes()

        isPlaying = false
    }

    private func prepareEngineIfNeeded() throws {
        guard !didPrepareEngine else {
            try restartEngineIfNeeded()
            return
        }

        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)

        try loadPianoSoundBank()
        try restartEngineIfNeeded()

        didPrepareEngine = true
    }

    private func restartEngineIfNeeded() throws {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            throw MIDIPlaybackError.engineStartFailed(error)
        }
    }

    private func loadPianoSoundBank() throws {
        let candidatePaths = [
            "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls",
            "/System/Library/Components/DLSMusicDevice.component/Contents/Resources/DefaultBankGS.sf2",
        ]

        for path in candidatePaths {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            do {
                try sampler.loadSoundBankInstrument(
                    at: url,
                    program: 0,
                    bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                    bankLSB: 0
                )
                return
            } catch {
                continue
            }
        }

        throw MIDIPlaybackError.soundBankNotFound
    }

    private func performPlayback(_ events: [ScheduledEvent]) async {
        let playbackStartedAt = Date()

        for event in events {
            let elapsed = Date().timeIntervalSince(playbackStartedAt)
            let delta = max(0, event.time - elapsed)
            if delta > 0 {
                let ns = UInt64(delta * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }

            guard !Task.isCancelled else { return }
            apply(event: event)
        }

        stopAllActiveNotes()
        guard !Task.isCancelled else { return }

        isPlaying = false
        playbackTask = nil
        onPlaybackFinished?()
    }

    private func apply(event: ScheduledEvent) {
        let note = UInt8(max(0, min(127, event.note)))
        let channel = UInt8(max(0, min(15, event.channel - 1)))
        let key = ActiveNoteKey(note: note, channel: channel)

        switch event.type {
            case let .noteOn(velocity):
                let clampedVelocity = UInt8(max(1, min(127, velocity)))
                sampler.startNote(note, withVelocity: clampedVelocity, onChannel: channel)
                activeNotes.insert(key)

            case .noteOff:
                sampler.stopNote(note, onChannel: channel)
                activeNotes.remove(key)
        }
    }

    private func stopAllActiveNotes() {
        for key in activeNotes {
            sampler.stopNote(key.note, onChannel: key.channel)
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
