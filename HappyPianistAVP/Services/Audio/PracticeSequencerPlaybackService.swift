import AudioToolbox
import AVFAudio
import Foundation

struct PracticeSequencerSequence: Sendable {
    let midiData: Data
    let durationSeconds: TimeInterval
    let events: [PracticeSequencerMIDIEvent]
    let outputApproximations: [PerformanceOutputApproximation]

    init(
        midiData: Data,
        durationSeconds: TimeInterval,
        events: [PracticeSequencerMIDIEvent],
        outputApproximations: [PerformanceOutputApproximation] = []
    ) {
        self.midiData = midiData
        self.durationSeconds = durationSeconds
        self.events = events
        self.outputApproximations = outputApproximations
    }
}

struct PracticePlaybackCommand: Equatable, Sendable {
    let sourceEventID: String
    let kind: PracticeSequencerMIDIEvent.Kind
}

protocol PracticeSequencerPlaybackServiceProtocol: AnyObject {
    func warmUp() async throws
    func stop(resetCommands: [PerformanceTransportCommand]) async
    func load(sequence: PracticeSequencerSequence) async throws
    func play(fromSeconds start: TimeInterval) async throws
    func currentSeconds() async -> TimeInterval
    func playOneShot(commands: [PracticePlaybackCommand], durationSeconds: TimeInterval) async throws
    func execute(commands: [PracticePlaybackCommand]) async throws
    func stopAllLiveNotes() async
}

struct PracticeAudioPlatformOperations: Sendable {
    let resolveSoundFontURL: @Sendable (String) -> URL?
    let configureAudioSession: @Sendable () throws -> Void
    let loadSoundBank: @Sendable (AVAudioUnitSampler, URL, UInt8) throws -> Void
    let startEngine: @Sendable (AVAudioEngine) throws -> Void
    let loadSequence: @Sendable (AVAudioSequencer, Data) throws -> Void
    let startSequence: @Sendable (AVAudioSequencer) throws -> Void
    let stopSequence: @Sendable (AVAudioSequencer) -> Void
    let sendMIDIEvent: @Sendable (AudioUnit, UInt32, UInt32, UInt32) -> OSStatus

    static let live = PracticeAudioPlatformOperations(
        resolveSoundFontURL: { resourceName in
            Bundle.main.url(forResource: resourceName, withExtension: "sf2")
        },
        configureAudioSession: {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        },
        loadSoundBank: { sampler, url, program in
            try sampler.loadSoundBankInstrument(
                at: url,
                program: program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: 0
            )
        },
        startEngine: { engine in
            engine.prepare()
            try engine.start()
        },
        loadSequence: { sequencer, data in
            try sequencer.load(from: data, options: [])
        },
        startSequence: { sequencer in
            try sequencer.start()
        },
        stopSequence: { sequencer in
            sequencer.stop()
        },
        sendMIDIEvent: { audioUnit, status, data1, data2 in
            MusicDeviceMIDIEvent(audioUnit, status, data1, data2, 0)
        }
    )
}

enum PracticeAudioSessionEvent: Equatable, Sendable {
    case interruptionBegan(reason: PianoPerformanceAudioLifecycleReason)
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(reason: PianoPerformanceAudioLifecycleReason)
    case mediaServicesReset
}

actor AVAudioSequencerPracticePlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private struct RecoveryContext {
        let operation: PianoPerformanceAudioOperation
        let recovery: PianoPerformanceAudioRecovery
        let reason: PianoPerformanceAudioLifecycleReason
    }

    private var engine: AVAudioEngine
    private var sampler: AVAudioUnitSampler
    private var sequencer: AVAudioSequencer
    private let userDefaults: UserDefaults
    private let platform: PracticeAudioPlatformOperations
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let stateHandler: @Sendable (PracticeAudioPlaybackState) -> Void

    private let soundFontResourceName: String
    private let program: UInt8
    private let channel: UInt8

    private var isReady = false
    private var isRecoveryBlocked = false
    private var playbackState: PracticeAudioPlaybackState = .idle
    private var pendingRecoveryContext: RecoveryContext?
    private var currentAudioOutputVolume: Float?
    private var volumeObservationTask: Task<Void, Never>?
    private var oneShotNoteBySourceEventID: [String: UInt8] = [:]
    private var oneShotStopTask: Task<Void, Never>?
    private var liveNoteBySourceEventID: [String: UInt8] = [:]
    private var noteBySourceEventID: [String: UInt8] = [:]
    private var audioSessionEventTasks: [Task<Void, Never>] = []

    init(
        soundFontResourceName: String,
        userDefaults: UserDefaults = .standard,
        program: UInt8 = 0,
        channel: UInt8 = 0,
        platform: PracticeAudioPlatformOperations = .live,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        stateHandler: @escaping @Sendable (PracticeAudioPlaybackState) -> Void = { _ in }
    ) {
        let graph = Self.makeAudioGraph()
        engine = graph.engine
        sampler = graph.sampler
        sequencer = graph.sequencer
        self.userDefaults = userDefaults
        self.platform = platform
        self.diagnosticsReporter = diagnosticsReporter
        self.stateHandler = stateHandler
        self.soundFontResourceName = soundFontResourceName
        self.program = program
        self.channel = channel

        let initialVolume = AudioOutputVolumeSettings.readAudioOutputVolume(from: userDefaults)
        currentAudioOutputVolume = initialVolume
        engine.mainMixerNode.outputVolume = initialVolume
    }

    deinit {
        volumeObservationTask?.cancel()
        oneShotStopTask?.cancel()
        for task in audioSessionEventTasks { task.cancel() }
    }

    func warmUp() throws {
        try ensureReady()
    }

    func stop(resetCommands: [PerformanceTransportCommand]) {
        haltPlayback()
        let resetFailure = executeReset(commands: resetCommands)
        recordResetMetrics(
            resetFailure: resetFailure,
            commands: resetCommands
        )
        guard let resetFailure else {
            if pendingRecoveryContext == nil {
                publishState(.idle)
            }
            return
        }
        engine.stop()
        isReady = false
        let error = PracticeAudioError.operationFailed(
            operation: .transportReset,
            recovery: .recoverable,
            detail: "MusicDeviceMIDIEvent failed: \(resetFailure)"
        )
        publishFailure(
            error,
            reason: .operationError,
            resetOutcome: .failed
        )
    }

    func load(sequence: PracticeSequencerSequence) throws {
        try ensureReady()
        applyAudioOutputVolumeIfNeeded()
        haltPlayback()

        do {
            try platform.loadSequence(sequencer, sequence.midiData)
        } catch {
            throw handleFailure(
                operationError(
                    operation: .sequenceLoad,
                    recovery: .recoverable,
                    underlying: error
                )
            )
        }

        noteBySourceEventID = Dictionary(
            sequence.events.compactMap { event -> (String, UInt8)? in
                guard let sourceEventID = event.sourceEventID,
                      case let .noteOn(midi, _) = event.kind,
                      let note = UInt8(exactly: midi)
                else { return nil }
                return (sourceEventID, note)
            },
            uniquingKeysWith: { first, _ in first }
        )
        sequencer.currentPositionInSeconds = 0

        for track in sequencer.tracks {
            track.destinationAudioUnit = sampler
        }
        sequencer.tempoTrack.destinationAudioUnit = sampler
        sequencer.prepareToPlay()
    }

    func play(fromSeconds start: TimeInterval) throws {
        try ensureReady()
        applyAudioOutputVolumeIfNeeded()

        sequencer.currentPositionInSeconds = max(0, start)
        do {
            try platform.startSequence(sequencer)
        } catch {
            throw handleFailure(
                operationError(
                    operation: .sequenceStart,
                    recovery: .recoverable,
                    underlying: error
                )
            )
        }
    }

    func currentSeconds() -> TimeInterval {
        sequencer.currentPositionInSeconds
    }

    func currentPlaybackState() -> PracticeAudioPlaybackState {
        playbackState
    }

    func playOneShot(commands: [PracticePlaybackCommand], durationSeconds: TimeInterval) throws {
        guard commands.isEmpty == false else { return }

        try ensureReady()
        applyAudioOutputVolumeIfNeeded()

        oneShotStopTask?.cancel()
        oneShotStopTask = nil
        stopOneShotNotes()

        do {
            try execute(commands: commands, tracking: .oneShot)
        } catch {
            throw handleFailure(audioError(from: error, operation: .commandRender))
        }

        oneShotStopTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, durationSeconds)))
            } catch {
                return
            }
            await self.stopOneShotNotes()
        }
    }

    func execute(commands: [PracticePlaybackCommand]) throws {
        try ensureReady()
        applyAudioOutputVolumeIfNeeded()
        do {
            try execute(commands: commands, tracking: .live)
        } catch {
            throw handleFailure(audioError(from: error, operation: .commandRender))
        }
    }

    func stopAllLiveNotes() {
        guard isReady else { return }
        for note in Set(liveNoteBySourceEventID.values) {
            sampler.stopNote(note, onChannel: channel)
        }
        liveNoteBySourceEventID.removeAll()
    }

    func handleAudioSessionEvent(_ event: PracticeAudioSessionEvent) {
        switch event {
        case let .interruptionBegan(reason):
            isRecoveryBlocked = true
            _ = handleFailure(
                PracticeAudioError.operationFailed(
                    operation: .interruption,
                    recovery: .recoverable,
                    detail: "Audio session interrupted"
                ),
                reason: reason
            )

        case let .interruptionEnded(shouldResume):
            isRecoveryBlocked = false
            guard shouldResume else { return }
            do {
                try ensureReady()
            } catch {
                return
            }

        case let .routeChanged(reason):
            guard reason != .routeCategoryChange else { return }
            _ = handleFailure(
                PracticeAudioError.operationFailed(
                    operation: .routeChange,
                    recovery: .recoverable,
                    detail: "Audio route changed"
                ),
                reason: reason
            )

        case .mediaServicesReset:
            _ = handleFailure(
                PracticeAudioError.operationFailed(
                    operation: .mediaServicesReset,
                    recovery: .recoverable,
                    detail: "Audio media services restarted"
                ),
                reason: .mediaServicesReset,
                rebuildAudioGraph: true
            )
        }
    }

    private static func makeAudioGraph() -> (
        engine: AVAudioEngine,
        sampler: AVAudioUnitSampler,
        sequencer: AVAudioSequencer
    ) {
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        return (engine, sampler, AVAudioSequencer(audioEngine: engine))
    }

    private func rebuildAudioGraph() {
        let graph = Self.makeAudioGraph()
        engine = graph.engine
        sampler = graph.sampler
        sequencer = graph.sequencer
        engine.mainMixerNode.outputVolume = currentAudioOutputVolume
            ?? AudioOutputVolumeSettings.readAudioOutputVolume(from: userDefaults)
        oneShotNoteBySourceEventID.removeAll()
        liveNoteBySourceEventID.removeAll()
        noteBySourceEventID.removeAll()
    }

    private func stopOneShotNotes() {
        guard isReady else { return }
        for note in Set(oneShotNoteBySourceEventID.values) {
            sampler.stopNote(note, onChannel: channel)
        }
        oneShotNoteBySourceEventID.removeAll()
    }

    private func haltPlayback() {
        oneShotStopTask?.cancel()
        oneShotStopTask = nil
        platform.stopSequence(sequencer)
        oneShotNoteBySourceEventID.removeAll()
        liveNoteBySourceEventID.removeAll()
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
                sampler.startNote(note, withVelocity: velocity, onChannel: channel)
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
                sampler.stopNote(note, onChannel: channel)

            case let .controlChange(controller, value):
                try sendMIDI(status: 0xB0 | channel, data1: controller, data2: value)
            case let .programChange(program):
                try sendMIDI(status: 0xC0 | channel, data1: program, data2: 0)
            case let .pitchBend(value):
                try sendMIDI(
                    status: 0xE0 | channel,
                    data1: UInt8(value & 0x7F),
                    data2: UInt8((value >> 7) & 0x7F)
                )
            case let .channelPressure(value):
                try sendMIDI(status: 0xD0 | channel, data1: value, data2: 0)
            case let .polyPressure(midi, value):
                guard let note = UInt8(exactly: midi) else { continue }
                try sendMIDI(status: 0xA0 | channel, data1: note, data2: value)
            }
        }
    }

    private func sendMIDI(status: UInt8, data1: UInt8, data2: UInt8) throws {
        let result = platform.sendMIDIEvent(
            sampler.audioUnit,
            UInt32(status),
            UInt32(data1),
            UInt32(data2)
        )
        guard result == noErr else {
            throw PracticeAudioError.operationFailed(
                operation: .commandRender,
                recovery: .recoverable,
                detail: "MusicDeviceMIDIEvent failed: \(result)"
            )
        }
    }

    private func executeReset(commands: [PerformanceTransportCommand]) -> OSStatus? {
        var firstFailure: OSStatus?
        for command in commands {
            let result: OSStatus?
            switch command {
            case let .noteOff(eventID):
                guard let note = noteBySourceEventID[eventID.description] else { continue }
                result = platform.sendMIDIEvent(
                    sampler.audioUnit,
                    UInt32(0x80 | channel),
                    UInt32(note),
                    0
                )
            case let .controlChange(controller, value):
                result = platform.sendMIDIEvent(
                    sampler.audioUnit,
                    UInt32(0xB0 | channel),
                    UInt32(controller),
                    UInt32(value)
                )
            case .allNotesOff:
                result = platform.sendMIDIEvent(
                    sampler.audioUnit,
                    UInt32(0xB0 | channel),
                    123,
                    0
                )
            case .allSoundOff:
                result = platform.sendMIDIEvent(
                    sampler.audioUnit,
                    UInt32(0xB0 | channel),
                    120,
                    0
                )
            }
            if let result, result != noErr, firstFailure == nil {
                firstFailure = result
            }
        }
        return firstFailure
    }

    private func recordResetMetrics(
        resetFailure: OSStatus?,
        commands: [PerformanceTransportCommand]
    ) {
        var metrics = PianoOutputMetricsAccumulator()
        metrics.recordReset(
            succeeded: resetFailure == nil,
            preventsStuckNotes: commands.contains { command in
                switch command {
                case .allNotesOff, .allSoundOff:
                    true
                case .noteOff, .controlChange:
                    false
                }
            }
        )
        diagnosticsReporter?.recordOutputMetrics(metrics.snapshot(capability: .localSampler))
    }

    private func ensureReady() throws {
        startObservingLifecycleIfNeeded()

        if isRecoveryBlocked {
            if case let .failed(error) = playbackState {
                throw error
            }
            throw PracticeAudioError.operationFailed(
                operation: .interruption,
                recovery: .recoverable,
                detail: "Audio session recovery is blocked until the interruption ends"
            )
        }

        do {
            try platform.configureAudioSession()
        } catch {
            throw handleFailure(
                operationError(
                    operation: .audioSessionConfiguration,
                    recovery: .recoverable,
                    underlying: error
                )
            )
        }

        if isReady {
            if engine.isRunning == false {
                do {
                    applyAudioOutputVolumeIfNeeded()
                    try platform.startEngine(engine)
                } catch {
                    throw handleFailure(
                        operationError(
                            operation: .engineStart,
                            recovery: .recoverable,
                            underlying: error
                        )
                    )
                }
            }
            publishReadyIfNeeded()
            return
        }

        guard let url = platform.resolveSoundFontURL(soundFontResourceName) else {
            throw handleFailure(
                PracticeAudioError.soundFontMissing(resourceName: soundFontResourceName)
            )
        }

        do {
            try platform.loadSoundBank(sampler, url, program)
        } catch {
            throw handleFailure(
                operationError(
                    operation: .soundFontLoad,
                    recovery: .unrecoverable,
                    underlying: error
                )
            )
        }

        do {
            applyAudioOutputVolumeIfNeeded()
            try platform.startEngine(engine)
        } catch {
            throw handleFailure(
                operationError(
                    operation: .engineStart,
                    recovery: .recoverable,
                    underlying: error
                )
            )
        }

        isReady = true
        publishReadyIfNeeded()
    }

    @discardableResult
    private func handleFailure(
        _ error: PracticeAudioError,
        reason: PianoPerformanceAudioLifecycleReason = .operationError,
        rebuildAudioGraph: Bool = false
    ) -> PracticeAudioError {
        let resetCommands = PerformanceTransportReducer.fullResetCommands
        haltPlayback()
        let resetFailure = executeReset(commands: resetCommands)
        recordResetMetrics(
            resetFailure: resetFailure,
            commands: resetCommands
        )
        engine.stop()
        isReady = false
        if rebuildAudioGraph {
            self.rebuildAudioGraph()
        }
        publishFailure(
            error,
            reason: reason,
            resetOutcome: resetFailure == nil ? .succeeded : .failed
        )
        return error
    }

    private func publishFailure(
        _ error: PracticeAudioError,
        reason: PianoPerformanceAudioLifecycleReason,
        resetOutcome: PianoPerformanceAudioResetOutcome
    ) {
        pendingRecoveryContext = RecoveryContext(
            operation: error.operation,
            recovery: error.recovery,
            reason: reason
        )
        publishState(.failed(error))
        diagnosticsReporter?.recordSystem(
            PianoPerformanceAudioDiagnosticSample(
                outcome: .failed,
                operation: error.operation,
                recovery: error.recovery,
                reason: reason,
                resetOutcome: resetOutcome
            ).diagnosticEvent
        )
    }

    private func publishReadyIfNeeded() {
        guard playbackState != .ready else { return }
        publishState(.ready)
        guard let recovery = pendingRecoveryContext else { return }
        pendingRecoveryContext = nil
        diagnosticsReporter?.recordSystem(
            PianoPerformanceAudioDiagnosticSample(
                outcome: .succeeded,
                operation: recovery.operation,
                recovery: recovery.recovery,
                reason: recovery.reason,
                resetOutcome: .notRequired
            ).diagnosticEvent
        )
    }

    private func publishState(_ state: PracticeAudioPlaybackState) {
        guard playbackState != state else { return }
        playbackState = state
        stateHandler(state)
    }

    private func operationError(
        operation: PianoPerformanceAudioOperation,
        recovery: PianoPerformanceAudioRecovery,
        underlying: any Error
    ) -> PracticeAudioError {
        PracticeAudioError.operationFailed(
            operation: operation,
            recovery: recovery,
            detail: underlying.localizedDescription
        )
    }

    private func audioError(
        from error: any Error,
        operation: PianoPerformanceAudioOperation
    ) -> PracticeAudioError {
        if let audioError = error as? PracticeAudioError {
            return audioError
        }
        return operationError(
            operation: operation,
            recovery: .recoverable,
            underlying: error
        )
    }

    private func startObservingLifecycleIfNeeded() {
        guard volumeObservationTask == nil, audioSessionEventTasks.isEmpty else { return }
        volumeObservationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                guard let self else { return }
                await self.applyAudioOutputVolumeIfNeeded()
            }
        }

        let notificationCenter = NotificationCenter.default
        audioSessionEventTasks = [
            Task { [weak self] in
                for await notification in notificationCenter.notifications(
                    named: AVAudioSession.interruptionNotification
                ) {
                    guard let self,
                          let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          let interruptionType = AVAudioSession.InterruptionType(rawValue: rawType)
                    else { continue }

                    switch interruptionType {
                    case .began:
                        let rawReason = notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
                        await self.handleAudioSessionEvent(
                            .interruptionBegan(reason: Self.interruptionReason(rawValue: rawReason))
                        )
                    case .ended:
                        let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                        let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                            .contains(.shouldResume)
                        await self.handleAudioSessionEvent(
                            .interruptionEnded(shouldResume: shouldResume)
                        )
                    @unknown default:
                        continue
                    }
                }
            },
            Task { [weak self] in
                for await notification in notificationCenter.notifications(
                    named: AVAudioSession.routeChangeNotification
                ) {
                    guard let self else { return }
                    let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                    await self.handleAudioSessionEvent(
                        .routeChanged(reason: Self.routeReason(rawValue: rawReason))
                    )
                }
            },
            Task { [weak self] in
                for await _ in notificationCenter.notifications(
                    named: AVAudioSession.mediaServicesWereResetNotification
                ) {
                    guard let self else { return }
                    await self.handleAudioSessionEvent(.mediaServicesReset)
                }
            },
        ]
    }

    private static func interruptionReason(rawValue: UInt?) -> PianoPerformanceAudioLifecycleReason {
        guard let rawValue,
              let reason = AVAudioSession.InterruptionReason(rawValue: rawValue)
        else { return .interruptionUnknown }
        switch reason {
        case .default:
            return .interruptionDefault
        case .appWasSuspended:
            return .interruptionAppSuspended
        case .builtInMicMuted:
            return .interruptionBuiltInMicMuted
        case .routeDisconnected:
            return .interruptionRouteDisconnected
        case .sceneWasBackgrounded:
            return .interruptionSceneBackgrounded
        @unknown default:
            return .interruptionUnknown
        }
    }

    private static func routeReason(rawValue: UInt?) -> PianoPerformanceAudioLifecycleReason {
        guard let rawValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawValue)
        else { return .routeUnknown }
        switch reason {
        case .unknown:
            return .routeUnknown
        case .newDeviceAvailable:
            return .routeNewDeviceAvailable
        case .oldDeviceUnavailable:
            return .routeOldDeviceUnavailable
        case .categoryChange:
            return .routeCategoryChange
        case .override:
            return .routeOverride
        case .wakeFromSleep:
            return .routeWakeFromSleep
        case .noSuitableRouteForCategory:
            return .routeNoSuitableRoute
        case .routeConfigurationChange:
            return .routeConfigurationChange
        @unknown default:
            return .routeUnknown
        }
    }

    private func applyAudioOutputVolumeIfNeeded() {
        let volume = AudioOutputVolumeSettings.readAudioOutputVolume(from: userDefaults)
        guard currentAudioOutputVolume != volume else { return }
        currentAudioOutputVolume = volume
        engine.mainMixerNode.outputVolume = volume
    }
}
