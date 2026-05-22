import Foundation

@MainActor
final class CoreMIDIPracticePlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private let outputService: any MIDIOutputSendingProtocol
    private let destinationUniqueID: Int32

    private let velocity: UInt8
    private let channel: UInt8

    private var loadedSequence: PracticeSequencerSequence?
    private var scheduler: MIDIEventScheduler?

    private var playingOneShotNotes: Set<UInt8> = []
    private var oneShotStopTask: Task<Void, Never>?
    private var liveNotes: Set<UInt8> = []

    private var lastKnownSeconds: TimeInterval = 0
    private var playbackStartedAtUptimeSeconds: TimeInterval?
    private var playbackStartSeconds: TimeInterval = 0

    init(
        destinationUniqueID: Int32,
        outputService: any MIDIOutputSendingProtocol = CoreMIDIOutputService(),
        velocity: UInt8 = 96,
        channel: UInt8 = 0
    ) {
        self.destinationUniqueID = destinationUniqueID
        self.outputService = outputService
        self.velocity = velocity
        self.channel = channel
    }

    func warmUp() throws {
        try ensureReady()
    }

    func stop() {
        oneShotStopTask?.cancel()
        oneShotStopTask = nil

        if let playbackStartedAtUptimeSeconds {
            lastKnownSeconds = playbackStartSeconds + max(0, ProcessInfo.processInfo.systemUptime - playbackStartedAtUptimeSeconds)
        }
        playbackStartedAtUptimeSeconds = nil

        Task { [scheduler] in
            await scheduler?.stop()
        }
        scheduler = nil

        stopAllLiveNotes()
        stopOneShotNotes()

        sendAllNotesOffBestEffort()
    }

    func load(sequence: PracticeSequencerSequence) throws {
        try ensureReady()
        stop()
        loadedSequence = sequence
        lastKnownSeconds = 0
    }

    func play(fromSeconds start: TimeInterval) throws {
        try ensureReady()
        guard let sequence = loadedSequence else { return }

        stop()

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

        let events = sequence.events
        Task.detached(priority: .userInitiated) {
            await scheduler.play(events: events, fromSeconds: startSeconds)
        }
    }

    func currentSeconds() -> TimeInterval {
        guard let playbackStartedAtUptimeSeconds else { return lastKnownSeconds }
        let now = ProcessInfo.processInfo.systemUptime
        let seconds = playbackStartSeconds + max(0, now - playbackStartedAtUptimeSeconds)
        if let loadedSequence {
            return min(seconds, loadedSequence.durationSeconds)
        }
        return seconds
    }

    func playOneShot(midiNotes: [Int], durationSeconds: TimeInterval) throws {
        let notes = midiNotes.compactMap { UInt8(exactly: $0) }
        guard notes.isEmpty == false else { return }

        try ensureReady()

        oneShotStopTask?.cancel()
        oneShotStopTask = nil

        stopOneShotNotes()

        for note in notes {
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

    private func sendAllNotesOffBestEffort() {
        try? outputService.sendAllNotesOff(channel: channel, destinationUniqueID: destinationUniqueID)
        try? outputService.sendAllSoundOff(channel: channel, destinationUniqueID: destinationUniqueID)
    }

    private func ensureReady() throws {
        try outputService.start()
    }
}

actor MIDIEventScheduler {
    private let outputService: any MIDIOutputSendingProtocol
    private let destinationUniqueID: Int32
    private let channel: UInt8

    private var playTask: Task<Void, Never>?
    private var playStartedAtUptimeSeconds: TimeInterval?
    private var playStartSeconds: TimeInterval = 0
    private(set) var currentSeconds: TimeInterval = 0

    init(outputService: any MIDIOutputSendingProtocol, destinationUniqueID: Int32, channel: UInt8) {
        self.outputService = outputService
        self.destinationUniqueID = destinationUniqueID
        self.channel = channel
    }

    func play(events: [PracticeSequencerMIDIEvent], fromSeconds startSeconds: TimeInterval) {
        stopInternal()

        playStartSeconds = startSeconds
        playStartedAtUptimeSeconds = ProcessInfo.processInfo.systemUptime
        currentSeconds = startSeconds

        let eventsToPlay = events.filter { $0.timeSeconds >= startSeconds }
        playTask = Task.detached(priority: .userInitiated) { [outputService, destinationUniqueID, channel] in
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

                do {
                    try Self.send(event: event, outputService: outputService, destinationUniqueID: destinationUniqueID, channel: channel)
                } catch {
                    // best-effort: ignore individual send failures
                }
                index += 1
            }
        }
    }

    func stop() {
        stopInternal()
    }

    func setCurrentSeconds(_ seconds: TimeInterval) {
        currentSeconds = seconds
    }

    private func stopInternal() {
        playTask?.cancel()
        playTask = nil
        playStartedAtUptimeSeconds = nil
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
