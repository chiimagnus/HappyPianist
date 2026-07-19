import CoreMIDI
import Foundation

@MainActor
final class CoreMIDIPracticePlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private let outputService: any MIDIOutputSendingProtocol
    private let destinationUniqueID: Int32
    private let outputCapabilities: PerformanceOutputCapabilities
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let hostTimeConverter: MIDIHostTimeConverter
    private let generationGuard = MIDIPlaybackGenerationGuard()

    private let channel: UInt8

    private var loadedDurationSeconds: TimeInterval?
    private var loadedEvents: [PracticeSequencerMIDIEvent]?
    private var scheduler: MIDILookAheadScheduler?
    private var schedulerTask: Task<Void, Never>?
    private var ownsOutputLifecycle = false

    private var oneShotNoteBySourceEventID: [String: UInt8] = [:]
    private var oneShotStopTask: Task<Void, Never>?
    private var liveNoteBySourceEventID: [String: UInt8] = [:]

    private var lastKnownSeconds: TimeInterval = 0
    private var playbackStartedAtUptimeSeconds: TimeInterval?
    private var playbackStartSeconds: TimeInterval = 0

    init(
        destinationUniqueID: Int32,
        outputService: (any MIDIOutputSendingProtocol)? = nil,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        outputCapabilities: PerformanceOutputCapabilities = .externalMIDI,
        hostTimeConverter: MIDIHostTimeConverter = MIDIHostTimeConverter(),
        channel: UInt8 = 0
    ) {
        self.destinationUniqueID = destinationUniqueID
        self.outputService = outputService ?? CoreMIDIOutputService(diagnosticsReporter: diagnosticsReporter)
        self.outputCapabilities = outputCapabilities
        self.diagnosticsReporter = diagnosticsReporter
        self.hostTimeConverter = hostTimeConverter
        self.channel = channel

        let generationGuard = self.generationGuard
        self.outputService.onDestinationRouteWillChange = {
            generationGuard.invalidate()
        }
        self.outputService.onDestinationRouteChange = { [weak self] in
            guard let self else { return Task {} }
            return Task { @MainActor in
                self.handleDestinationRouteChange()
            }
        }
    }

    isolated deinit {
        let hadScheduledPlayback = schedulerTask != nil
        outputService.onDestinationRouteWillChange = nil
        outputService.onDestinationRouteChange = nil
        generationGuard.invalidate()
        oneShotStopTask?.cancel()
        schedulerTask?.cancel()
        guard ownsOutputLifecycle else { return }

        if hadScheduledPlayback {
            do {
                try outputService.flushScheduledMessages(destinationUniqueID: destinationUniqueID)
            } catch {
                diagnosticsReporter?.recordSystem(
                    severity: .error,
                    category: .midi,
                    stage: "coreMIDI.teardownFlush",
                    summary: "释放外部 MIDI 播放服务时取消未来事件失败",
                    reason: String(describing: type(of: error))
                )
            }
        }
        execute(PerformanceTransportReducer.fullResetCommands)
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
        recordControllerApproximations(in: sequence.events)
    }

    func play(fromSeconds start: TimeInterval) throws {
        try ensureReady()
        guard let events = loadedEvents else { return }

        haltPlayback()

        let startSeconds = max(0, start)
        lastKnownSeconds = startSeconds
        playbackStartSeconds = startSeconds
        playbackStartedAtUptimeSeconds = ProcessInfo.processInfo.systemUptime
        let generation = generationGuard.beginGeneration()

        let scheduler = MIDILookAheadScheduler(
            outputService: outputService,
            destinationUniqueID: destinationUniqueID,
            channel: channel,
            outputCapabilities: outputCapabilities,
            hostTimeConverter: hostTimeConverter,
            diagnosticsReporter: diagnosticsReporter,
            generationGuard: generationGuard,
            generation: generation
        )
        self.scheduler = scheduler
        schedulerTask = scheduler.start(events: events, fromSeconds: startSeconds)
    }

    private func haltPlayback() {
        generationGuard.invalidate()
        oneShotStopTask?.cancel()
        oneShotStopTask = nil

        if let playbackStartedAtUptimeSeconds {
            lastKnownSeconds = playbackStartSeconds + max(0, ProcessInfo.processInfo.systemUptime - playbackStartedAtUptimeSeconds)
        }
        playbackStartedAtUptimeSeconds = nil

        let hadScheduledPlayback = schedulerTask != nil
        schedulerTask?.cancel()
        schedulerTask = nil
        scheduler = nil

        if hadScheduledPlayback {
            do {
                try outputService.flushScheduledMessages(destinationUniqueID: destinationUniqueID)
            } catch {
                diagnosticsReporter?.recordSystem(
                    severity: .error,
                    category: .midi,
                    stage: "coreMIDI.playbackFlush",
                    summary: "停止外部 MIDI 播放时取消未来事件失败",
                    reason: String(describing: type(of: error))
                )
            }
        }

        liveNoteBySourceEventID.removeAll()
        oneShotNoteBySourceEventID.removeAll()
    }

    private func handleDestinationRouteChange() {
        guard ownsOutputLifecycle else { return }
        haltPlayback()
        execute(PerformanceTransportReducer.fullResetCommands)
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

    func playOneShot(commands: [PracticePlaybackCommand], durationSeconds: TimeInterval) throws {
        guard commands.isEmpty == false else { return }

        try ensureReady()

        oneShotStopTask?.cancel()
        oneShotStopTask = nil

        stopOneShotNotes()

        try execute(commands: commands, tracking: .oneShot)

        oneShotStopTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, durationSeconds)))
            } catch {
                return
            }
            guard Task.isCancelled == false else { return }
            await MainActor.run { [weak self] in
                self?.stopOneShotNotes()
            }
        }
    }

    func execute(commands: [PracticePlaybackCommand]) throws {
        try ensureReady()
        try execute(commands: commands, tracking: .live)
    }

    func stopAllLiveNotes() {
        for note in Set(liveNoteBySourceEventID.values) {
            do {
                try outputService.sendNoteOff(note: note, channel: channel, destinationUniqueID: destinationUniqueID)
            } catch {
                diagnosticsReporter?.recordSystem(
                    severity: .error,
                    category: .midi,
                    stage: "coreMIDI.stopLiveNote",
                    summary: "停止实时 MIDI 音符失败",
                    reason: String(describing: type(of: error))
                )
            }
        }
        liveNoteBySourceEventID.removeAll()
    }

    private func stopOneShotNotes() {
        for note in Set(oneShotNoteBySourceEventID.values) {
            do {
                try outputService.sendNoteOff(note: note, channel: channel, destinationUniqueID: destinationUniqueID)
            } catch {
                diagnosticsReporter?.recordSystem(
                    severity: .error,
                    category: .midi,
                    stage: "coreMIDI.stopOneShotNote",
                    summary: "停止预览 MIDI 音符失败",
                    reason: String(describing: type(of: error))
                )
            }
        }
        oneShotNoteBySourceEventID.removeAll()
    }

    private enum CommandTracking {
        case live
        case oneShot
    }

    private func execute(
        commands: [PracticePlaybackCommand],
        tracking: CommandTracking
    ) throws {
        for command in commands {
            switch command.kind {
            case let .noteOn(midi, velocity):
                guard let note = UInt8(exactly: midi) else { continue }
                try outputService.sendNoteOn(
                    note: note,
                    velocity: velocity,
                    channel: channel,
                    destinationUniqueID: destinationUniqueID
                )
                switch tracking {
                case .live:
                    liveNoteBySourceEventID[command.sourceEventID] = note
                case .oneShot:
                    oneShotNoteBySourceEventID[command.sourceEventID] = note
                }

            case let .noteOff(midi):
                let trackedNote: UInt8?
                switch tracking {
                case .live:
                    trackedNote = liveNoteBySourceEventID.removeValue(forKey: command.sourceEventID)
                case .oneShot:
                    trackedNote = oneShotNoteBySourceEventID.removeValue(forKey: command.sourceEventID)
                }
                guard let note = trackedNote ?? UInt8(exactly: midi) else { continue }
                try outputService.sendNoteOff(
                    note: note,
                    channel: channel,
                    destinationUniqueID: destinationUniqueID
                )

            case let .controlChange(controller, value):
                let resolution = outputCapabilities.resolve(controllerNumber: controller, value: value)
                try outputService.sendControlChange(
                    controller: controller,
                    value: resolution.value,
                    channel: channel,
                    destinationUniqueID: destinationUniqueID
                )
            case let .programChange(program):
                try outputService.sendProgramChange(
                    program: program,
                    channel: channel,
                    destinationUniqueID: destinationUniqueID
                )
            case let .pitchBend(value):
                try outputService.sendMIDI1Bytes([
                    0xE0 | (channel & 0x0F),
                    UInt8(value & 0x7F),
                    UInt8((value >> 7) & 0x7F),
                ], destinationUniqueID: destinationUniqueID)
            case let .channelPressure(value):
                try outputService.sendMIDI1Bytes(
                    [0xD0 | (channel & 0x0F), value],
                    destinationUniqueID: destinationUniqueID
                )
            case let .polyPressure(midi, value):
                guard let note = UInt8(exactly: midi) else { continue }
                try outputService.sendMIDI1Bytes(
                    [0xA0 | (channel & 0x0F), note, value],
                    destinationUniqueID: destinationUniqueID
                )
            }
        }
    }

    private func execute(_ commands: [PerformanceTransportCommand]) {
        var failureCount = 0
        for command in commands {
            do {
                switch command {
                case let .noteOff(eventID):
                    guard let note = loadedEvents?.lazy.compactMap({ event -> UInt8? in
                        guard event.sourceEventID == eventID.description,
                              case let .noteOn(midi, _) = event.kind
                        else { return nil }
                        return UInt8(exactly: midi)
                    }).first else { continue }
                    try outputService.sendNoteOff(
                        note: note,
                        channel: channel,
                        destinationUniqueID: destinationUniqueID
                    )
                case let .controlChange(controller, value):
                    let resolution = outputCapabilities.resolve(controllerNumber: controller, value: value)
                    try outputService.sendControlChange(
                        controller: controller,
                        value: resolution.value,
                        channel: channel,
                        destinationUniqueID: destinationUniqueID
                    )
                case .allNotesOff:
                    try outputService.sendAllNotesOff(
                        channel: channel,
                        destinationUniqueID: destinationUniqueID
                    )
                case .allSoundOff:
                    try outputService.sendAllSoundOff(
                        channel: channel,
                        destinationUniqueID: destinationUniqueID
                    )
                }
            } catch {
                failureCount += 1
            }
        }
        if commands.isEmpty == false {
            var metrics = PianoOutputMetricsAccumulator()
            metrics.recordReset(
                succeeded: failureCount == 0,
                preventsStuckNotes: commands.contains { command in
                    switch command {
                    case .allNotesOff, .allSoundOff:
                        true
                    case .noteOff, .controlChange:
                        false
                    }
                }
            )
            diagnosticsReporter?.recordOutputMetrics(metrics.snapshot(capability: .externalMIDI))
        }
        guard failureCount > 0 else { return }
        diagnosticsReporter?.recordSystem(
            severity: .error,
            category: .midi,
            stage: "coreMIDI.transportReset",
            summary: "外部 MIDI 停止复位未完全发送",
            reason: "failureCount=\(failureCount)"
        )
    }

    private func ensureReady() throws {
        guard ownsOutputLifecycle == false else { return }
        try outputService.start()
        ownsOutputLifecycle = true
    }

    private func recordControllerApproximations(in events: [PracticeSequencerMIDIEvent]) {
        let count = events.reduce(into: 0) { count, event in
            guard case let .controlChange(controller, value) = event.kind,
                  outputCapabilities.resolve(controllerNumber: controller, value: value).approximation != nil
            else { return }
            count += 1
        }
        guard count > 0 else { return }
        diagnosticsReporter?.recordSystem(
            severity: .info,
            category: .midi,
            stage: "coreMIDI.controllerCapability",
            summary: "外部 MIDI 控制器值已按输出能力量化",
            reason: "approximationCount=\(count)"
        )
    }
}
