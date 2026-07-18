import Foundation
import os

@MainActor
final class CoreMIDIPracticePlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private let outputService: any MIDIOutputSendingProtocol
    private let destinationUniqueID: Int32

    private let velocity: UInt8
    private let channel: UInt8

    private var loadedDurationSeconds: TimeInterval?
    private var loadedEvents: [PracticeSequencerMIDIEvent]?
    private var scheduler: MIDIEventScheduler?

    private var playingOneShotNotes: Set<UInt8> = []
    private var oneShotStopTask: Task<Void, Never>?
    private var liveNotes: Set<UInt8> = []

    private var lastKnownSeconds: TimeInterval = 0
    private var playbackStartedAtUptimeSeconds: TimeInterval?
    private var playbackStartSeconds: TimeInterval = 0

    init(
        destinationUniqueID: Int32,
        outputService: (any MIDIOutputSendingProtocol)? = nil,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        velocity: UInt8 = 96,
        channel: UInt8 = 0
    ) {
        self.destinationUniqueID = destinationUniqueID
        self.outputService = outputService ?? CoreMIDIOutputService(diagnosticsReporter: diagnosticsReporter)
        self.velocity = velocity
        self.channel = channel
    }

    func warmUp() throws {
        try ensureReady()
    }

    func stop(resetCommands: [PerformanceTransportCommand]) {
        haltPlayback()
        execute(resetCommands)
    }

    func load(sequence: PracticeSequencerSequence) throws {
        try ensureReady()
        haltPlayback()
        loadedDurationSeconds = sequence.durationSeconds
        loadedEvents = sequence.events
        lastKnownSeconds = 0
    }

    func play(fromSeconds start: TimeInterval) throws {
        try ensureReady()
        guard let events = loadedEvents else { return }

        haltPlayback()

        let startSeconds = max(0, start)
        lastKnownSeconds = startSeconds
        playbackStartSeconds = startSeconds
        playbackStartedAtUptimeSeconds = ProcessInfo.processInfo.systemUptime

        let scheduler = MIDIEventScheduler(
            outputService: outputService,
            destinationUniqueID: destinationUniqueID,
            channel: channel
        )
        self.scheduler = scheduler

        scheduler.play(events: events, fromSeconds: startSeconds)
    }

    private func haltPlayback() {
        oneShotStopTask?.cancel()
        oneShotStopTask = nil

        if let playbackStartedAtUptimeSeconds {
            lastKnownSeconds = playbackStartSeconds + max(0, ProcessInfo.processInfo.systemUptime - playbackStartedAtUptimeSeconds)
        }
        playbackStartedAtUptimeSeconds = nil

        scheduler?.stop()
        scheduler = nil

        liveNotes.removeAll()
        playingOneShotNotes.removeAll()
    }

    func currentSeconds() -> TimeInterval {
        guard let playbackStartedAtUptimeSeconds else { return lastKnownSeconds }
        let now = ProcessInfo.processInfo.systemUptime
        let seconds = playbackStartSeconds + max(0, now - playbackStartedAtUptimeSeconds)
        if let loadedDurationSeconds {
            return min(seconds, loadedDurationSeconds)
        }
        return seconds
    }

    func playOneShot(noteOns: [PracticeOneShotNoteOn], durationSeconds: TimeInterval) throws {
        let notes = noteOns.compactMap { noteOn -> (note: UInt8, velocity: UInt8)? in
            guard let note = UInt8(exactly: noteOn.midiNote) else { return nil }
            return (note, noteOn.velocity)
        }
        guard notes.isEmpty == false else { return }

        try ensureReady()

        oneShotStopTask?.cancel()
        oneShotStopTask = nil

        stopOneShotNotes()

        for (note, velocity) in notes {
            try? outputService.sendNoteOn(
                note: note,
                velocity: velocity,
                channel: channel,
                destinationUniqueID: destinationUniqueID
            )
            playingOneShotNotes.insert(note)
        }

        oneShotStopTask = Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, durationSeconds)))
            guard Task.isCancelled == false else { return }
            await MainActor.run { [weak self] in
                self?.stopOneShotNotes()
            }
        }
    }

    func startLiveNotes(midiNotes: Set<Int>) throws {
        try ensureReady()
        for midiNote in midiNotes {
            guard let note = UInt8(exactly: midiNote), liveNotes.contains(note) == false else { continue }
            try? outputService.sendNoteOn(
                note: note,
                velocity: velocity,
                channel: channel,
                destinationUniqueID: destinationUniqueID
            )
            liveNotes.insert(note)
        }
    }

    func stopLiveNotes(midiNotes: Set<Int>) {
        for midiNote in midiNotes {
            guard let note = UInt8(exactly: midiNote), liveNotes.contains(note) else { continue }
            try? outputService.sendNoteOff(note: note, channel: channel, destinationUniqueID: destinationUniqueID)
            liveNotes.remove(note)
        }
    }

    func stopAllLiveNotes() {
        for note in liveNotes {
            try? outputService.sendNoteOff(note: note, channel: channel, destinationUniqueID: destinationUniqueID)
        }
        liveNotes.removeAll()
    }

    private func stopOneShotNotes() {
        for note in playingOneShotNotes {
            try? outputService.sendNoteOff(note: note, channel: channel, destinationUniqueID: destinationUniqueID)
        }
        playingOneShotNotes.removeAll()
    }

    private func execute(_ commands: [PerformanceTransportCommand]) {
        for command in commands {
            switch command {
            case let .noteOff(eventID):
                guard let note = loadedEvents?.lazy.compactMap({ event -> UInt8? in
                    guard event.sourceEventID == eventID.description,
                          case let .noteOn(midi, _) = event.kind
                    else { return nil }
                    return UInt8(exactly: midi)
                }).first else { continue }
                try? outputService.sendNoteOff(
                    note: note,
                    channel: channel,
                    destinationUniqueID: destinationUniqueID
                )
            case let .controlChange(controller, value):
                try? outputService.sendControlChange(
                    controller: controller,
                    value: value,
                    channel: channel,
                    destinationUniqueID: destinationUniqueID
                )
            case .allNotesOff:
                try? outputService.sendAllNotesOff(channel: channel, destinationUniqueID: destinationUniqueID)
            case .allSoundOff:
                try? outputService.sendAllSoundOff(channel: channel, destinationUniqueID: destinationUniqueID)
            }
        }
    }

    private func ensureReady() throws {
        try outputService.start()
    }
}

private final class MIDIEventScheduler: Sendable {
    private struct State {
        var generation = 0
        var playTask: Task<Void, Never>?
    }

    private let outputService: any MIDIOutputSendingProtocol
    private let destinationUniqueID: Int32
    private let channel: UInt8
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(outputService: any MIDIOutputSendingProtocol, destinationUniqueID: Int32, channel: UInt8) {
        self.outputService = outputService
        self.destinationUniqueID = destinationUniqueID
        self.channel = channel
    }

    func play(events: [PracticeSequencerMIDIEvent], fromSeconds startSeconds: TimeInterval) {
        let eventsToPlay = events.filter { $0.timeSeconds >= startSeconds }
        let generation = state.withLock { state in
            state.playTask?.cancel()
            state.generation += 1
            return state.generation
        }
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let startedAt = ProcessInfo.processInfo.systemUptime
            var index = 0

            while index < eventsToPlay.count, Task.isCancelled == false {
                let event = eventsToPlay[index]
                let targetUptime = startedAt + max(0, event.timeSeconds - startSeconds)
                let now = ProcessInfo.processInfo.systemUptime
                let wait = max(0, targetUptime - now)
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                    guard Task.isCancelled == false else { break }
                }

                guard sendIfCurrent(event, generation: generation) else { break }
                index += 1
            }
        }
        state.withLock { state in
            guard state.generation == generation else {
                task.cancel()
                return
            }
            state.playTask = task
        }
    }

    func stop() {
        let task = state.withLock { state in
            state.generation += 1
            defer { state.playTask = nil }
            return state.playTask
        }
        task?.cancel()
    }

    private func sendIfCurrent(_ event: PracticeSequencerMIDIEvent, generation: Int) -> Bool {
        state.withLock { state in
            guard state.generation == generation else { return false }
            do {
                try Self.send(
                    event: event,
                    outputService: outputService,
                    destinationUniqueID: destinationUniqueID,
                    channel: channel
                )
            } catch {
                // best-effort: ignore individual send failures
            }
            return true
        }
    }

    private static func send(
        event: PracticeSequencerMIDIEvent,
        outputService: any MIDIOutputSendingProtocol,
        destinationUniqueID: Int32,
        channel: UInt8
    ) throws {
        switch event.kind {
        case let .noteOn(midi, velocity):
            guard let note = UInt8(exactly: midi) else { return }
            try outputService.sendNoteOn(note: note, velocity: velocity, channel: channel, destinationUniqueID: destinationUniqueID)
        case let .noteOff(midi):
            guard let note = UInt8(exactly: midi) else { return }
            try outputService.sendNoteOff(note: note, channel: channel, destinationUniqueID: destinationUniqueID)
        case let .controlChange(controller, value):
            try outputService.sendControlChange(controller: controller, value: value, channel: channel, destinationUniqueID: destinationUniqueID)
        case let .programChange(program):
            try outputService.sendProgramChange(program: program, channel: channel, destinationUniqueID: destinationUniqueID)
        case let .pitchBend(value):
            let lsb = UInt8(value & 0x7F)
            let msb = UInt8((value >> 7) & 0x7F)
            let status: UInt8 = 0xE0 | (channel & 0x0F)
            try outputService.sendMIDI1Bytes([status, lsb, msb], destinationUniqueID: destinationUniqueID)
        case let .channelPressure(value):
            let status: UInt8 = 0xD0 | (channel & 0x0F)
            try outputService.sendMIDI1Bytes([status, value], destinationUniqueID: destinationUniqueID)
        case let .polyPressure(midi, value):
            guard let note = UInt8(exactly: midi) else { return }
            let status: UInt8 = 0xA0 | (channel & 0x0F)
            try outputService.sendMIDI1Bytes([status, note, value], destinationUniqueID: destinationUniqueID)
        }
    }
}
