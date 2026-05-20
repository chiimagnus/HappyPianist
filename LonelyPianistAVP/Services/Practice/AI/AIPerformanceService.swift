import Foundation
import os

@MainActor
protocol AIPerformancePracticeSessionProtocol: AnyObject {
    var autoplayState: PracticeSessionAutoplayState { get }
    var isManualReplayPlaying: Bool { get }
    var currentStep: PracticeStep? { get }
    var autoplayTimeline: AutoplayPerformanceTimeline { get }
    var tempoMap: MusicXMLTempoMap { get }
    var pedalTimeline: MusicXMLPedalTimeline? { get }
    var sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol { get }

    func aiPerformanceTickRange(maxMeasures: Int) -> (startTick: Int, endTick: Int)?
    func stopVirtualPianoInput()
    func stopAudioRecognition()
    func prepareAudioRecognitionSuppressWindowForPlayback() -> Date
    func refreshAudioRecognitionForCurrentState()
}

@MainActor
protocol AIPerformanceBackendDiscoveryServiceProtocol: AnyObject {
    var resolvedEndpoint: (host: String, port: Int)? { get }
    func start()
    func stop()
}

extension BonjourBackendDiscoveryService: AIPerformanceBackendDiscoveryServiceProtocol {}

@MainActor
final class AIPerformanceService {
    struct State: Equatable {
        var isAIPerformanceActive: Bool
        var latestSchedule: [PracticeSequencerMIDIEvent]
        var lastImprovStatusText: String?
    }

    private let logger: Logger
    private let nowUptimeSeconds: () -> TimeInterval
    private let backendDiscoveryService: any AIPerformanceBackendDiscoveryServiceProtocol
    private let backendClient: any ImprovBackendClientProtocol
    private let pollInterval: Duration
    private let silenceTimeoutSeconds: TimeInterval
    private let onStateChanged: @MainActor (State) -> Void

    private weak var practiceSession: (any AIPerformancePracticeSessionProtocol)?

    private var hasShutdown = false
    private var isEnabled = false

    private var silenceTrigger = NoteOnSilenceTrigger()
    private var phraseRecorder = PhraseRecorder()

    private var pollTask: Task<Void, Never>?

    private var isAIPerformanceActive = false
    private var latestSchedule: [PracticeSequencerMIDIEvent] = []
    private var lastImprovStatusText: String?

    init(
        logger: Logger,
        nowUptimeSeconds: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        backendDiscoveryService: any AIPerformanceBackendDiscoveryServiceProtocol,
        backendClient: (any ImprovBackendClientProtocol)? = nil,
        pollInterval: Duration = .milliseconds(100),
        silenceTimeoutSeconds: TimeInterval = 2.0,
        onStateChanged: @escaping @MainActor (State) -> Void
    ) {
        self.logger = logger
        self.nowUptimeSeconds = nowUptimeSeconds
        self.backendDiscoveryService = backendDiscoveryService
        self.backendClient = backendClient ?? ImprovBackendClient()
        self.pollInterval = pollInterval
        self.silenceTimeoutSeconds = silenceTimeoutSeconds
        self.onStateChanged = onStateChanged
    }

    func shutdown() {
        guard hasShutdown == false else { return }
        hasShutdown = true
        setEnabled(false)
    }

    func updatePracticeSession(_ session: any AIPerformancePracticeSessionProtocol) {
        practiceSession = session
    }

    func setEnabled(_ enabled: Bool) {
        guard hasShutdown == false else { return }
        if enabled == false {
            guard isEnabled || pollTask != nil else { return }

            isEnabled = false
            backendDiscoveryService.stop()
            pollTask?.cancel()
            pollTask = nil

            isAIPerformanceActive = false
            silenceTrigger.reset()
            phraseRecorder.reset()
            lastImprovStatusText = nil
            latestSchedule = []
            notifyStateChanged()

            stopPlaybackAndRestoreAudioRecognitionIfNeeded()
            return
        }

        if isEnabled, pollTask != nil {
            return
        }

        let wasEnabled = isEnabled
        isEnabled = true

        backendDiscoveryService.start()

        if wasEnabled == false {
            silenceTrigger.reset()
            phraseRecorder.reset()
        }

        guard pollTask == nil else { return }
        guard practiceSession?.currentStep != nil else { return }

        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while Task.isCancelled == false {
                guard isEnabled else { return }
                await pollAndPlayAIPerformanceIfNeeded()
                do {
                    try await Task.sleep(for: pollInterval)
                } catch {
                    return
                }
            }
        }
    }

    func recordMIDI1EventForPhraseRecordingIfNeeded(_ event: MIDI1InputEvent) {
        guard isEnabled else { return }

        switch event.kind {
        case let .noteOn(note, velocity):
            silenceTrigger.recordNoteOn(atUptime: event.receivedAtUptimeSeconds)
            phraseRecorder.recordNoteOn(midi: note, velocity: velocity, timestamp: event.receivedAtUptimeSeconds)
        case let .noteOff(note, _):
            phraseRecorder.recordNoteOff(midi: note, timestamp: event.receivedAtUptimeSeconds)
        default:
            return
        }
    }

    func recordMIDI2EventForPhraseRecordingIfNeeded(_ event: MIDI2InputEvent) {
        guard isEnabled else { return }

        switch event.kind {
        case let .noteOn(note, velocity16):
            silenceTrigger.recordNoteOn(atUptime: event.receivedAtUptimeSeconds)
            phraseRecorder.recordNoteOn(
                midi: note,
                velocity: MIDI2ValueMapping.value16To7Bit(velocity16),
                timestamp: event.receivedAtUptimeSeconds
            )
        case let .noteOff(note, _):
            phraseRecorder.recordNoteOff(midi: note, timestamp: event.receivedAtUptimeSeconds)
        default:
            return
        }
    }

    func recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: Bool,
        keyContact: KeyContactResult,
        nowUptimeSeconds: TimeInterval
    ) {
        guard usesBluetoothMIDIInput == false else { return }
        guard isEnabled else { return }
        guard isAIPerformanceActive == false else { return }

        if keyContact.started.isEmpty == false {
            silenceTrigger.recordNoteOn(atUptime: nowUptimeSeconds)
            for note in keyContact.started {
                phraseRecorder.recordNoteOn(midi: note, velocity: 90, timestamp: nowUptimeSeconds)
            }
        }
        if keyContact.ended.isEmpty == false {
            for note in keyContact.ended {
                phraseRecorder.recordNoteOff(midi: note, timestamp: nowUptimeSeconds)
            }
        }
    }

    private func notifyStateChanged() {
        onStateChanged(
            State(
                isAIPerformanceActive: isAIPerformanceActive,
                latestSchedule: latestSchedule,
                lastImprovStatusText: lastImprovStatusText
            )
        )
    }

    private func stopPlaybackAndRestoreAudioRecognitionIfNeeded() {
        guard let practiceSession else { return }
        practiceSession.stopVirtualPianoInput()
        practiceSession.sequencerPlaybackService.stop()
        practiceSession.refreshAudioRecognitionForCurrentState()
    }

    private func pollAndPlayAIPerformanceIfNeeded() async {
        guard isAIPerformanceActive == false else { return }
        guard let practiceSession else { return }
        guard practiceSession.autoplayState == .off else { return }
        guard practiceSession.isManualReplayPlaying == false else { return }

        let nowUptime = nowUptimeSeconds()
        guard silenceTrigger.pollShouldTrigger(atUptime: nowUptime, timeoutSeconds: silenceTimeoutSeconds) else { return }

        isAIPerformanceActive = true
        notifyStateChanged()

        defer {
            isAIPerformanceActive = false
            silenceTrigger.reset()
            notifyStateChanged()
        }

        let phrase = phraseRecorder.flushPhrase(endTimestamp: nowUptime)
        if phrase.isEmpty == false {
            let didPlayBackend = await attemptBackendImprov(promptNotes: phrase)
            if didPlayBackend {
                return
            }
        } else {
            lastImprovStatusText = "Last improv: fallback(emptyPhrase)"
            notifyStateChanged()
        }

        if let tickRange = practiceSession.aiPerformanceTickRange(maxMeasures: 2) {
            await playAIPerformanceTickRange(tickRange)
        }
    }

    private func attemptBackendImprov(promptNotes: [ImprovDialogueNote]) async -> Bool {
        guard practiceSession != nil else { return false }
        guard let resolved = backendDiscoveryService.resolvedEndpoint else {
            lastImprovStatusText = "Last improv: fallback(backendNotFound)"
            notifyStateChanged()
            return false
        }

        let params = ImprovGenerateParams(topP: 0.95, maxTokens: 256, strategy: "deterministic")
        let request = ImprovGenerateRequest(notes: promptNotes, params: params, sessionID: nil)

        let response: ImprovResultResponse
        do {
            response = try await backendClient.generate(
                host: resolved.host,
                port: resolved.port,
                request: request,
                timeoutSeconds: 2
            )
        } catch let error as URLError where error.code == .timedOut {
            lastImprovStatusText = "Last improv: fallback(timeout)"
            notifyStateChanged()
            return false
        } catch {
            logger.warning("improv backend failed: \(String(describing: error), privacy: .public)")
            lastImprovStatusText = "Last improv: fallback(error)"
            notifyStateChanged()
            return false
        }

        let schedule = ImprovScheduleBuilder().buildSchedule(from: response.notes)
        guard schedule.isEmpty == false else {
            lastImprovStatusText = "Last improv: fallback(emptyReply)"
            notifyStateChanged()
            return false
        }

        await playAIPerformanceSchedule(schedule)
        lastImprovStatusText = "Last improv: backend"
        notifyStateChanged()
        return true
    }

    private func playAIPerformanceSchedule(_ schedule: [PracticeSequencerMIDIEvent]) async {
        guard let practiceSession else { return }

        practiceSession.stopVirtualPianoInput()
        practiceSession.sequencerPlaybackService.stop()
        practiceSession.stopAudioRecognition()
        latestSchedule = []
        notifyStateChanged()

        var didStartPlayback = false
        defer {
            if didStartPlayback == false {
                practiceSession.sequencerPlaybackService.stop()
                if isEnabled {
                    practiceSession.refreshAudioRecognitionForCurrentState()
                }
            }
        }

        do {
            try practiceSession.sequencerPlaybackService.warmUp()
        } catch {
            return
        }

        let sequence: PracticeSequencerSequence
        do {
            sequence = try await Task.detached(priority: .userInitiated) {
                try PracticeSequencerSequenceBuilder().buildSequence(from: schedule)
            }.value
        } catch {
            return
        }

        latestSchedule = schedule
        notifyStateChanged()

        do {
            try practiceSession.sequencerPlaybackService.load(sequence: sequence)
            try practiceSession.sequencerPlaybackService.play(fromSeconds: 0)
        } catch {
            return
        }
        didStartPlayback = true

        let sequenceEndSeconds = max(0, sequence.durationSeconds)
        while Task.isCancelled == false {
            guard isEnabled else { break }
            let nowSeconds = practiceSession.sequencerPlaybackService.currentSeconds()
            if nowSeconds >= sequenceEndSeconds {
                break
            }
            try? await Task.sleep(for: .milliseconds(33))
        }

        practiceSession.sequencerPlaybackService.stop()
        if isEnabled {
            _ = practiceSession.prepareAudioRecognitionSuppressWindowForPlayback()
            practiceSession.refreshAudioRecognitionForCurrentState()
        }
    }

    private func playAIPerformanceTickRange(_ tickRange: (startTick: Int, endTick: Int)) async {
        guard let practiceSession else { return }

        practiceSession.stopVirtualPianoInput()
        practiceSession.sequencerPlaybackService.stop()
        practiceSession.stopAudioRecognition()
        latestSchedule = []
        notifyStateChanged()

        var didStartPlayback = false
        defer {
            if didStartPlayback == false {
                practiceSession.sequencerPlaybackService.stop()
                if isEnabled {
                    practiceSession.refreshAudioRecognitionForCurrentState()
                }
            }
        }

        let timelineSnapshot = practiceSession.autoplayTimeline
        let tempoMapSnapshot = practiceSession.tempoMap
        let initialSustainPedalDown = practiceSession.pedalTimeline?.isDown(atTick: tickRange.startTick) ?? false
        let leadInSeconds: TimeInterval = 0.05

        do {
            try practiceSession.sequencerPlaybackService.warmUp()
        } catch {
            return
        }

        let scheduleAndSequence: (schedule: [PracticeSequencerMIDIEvent], sequence: PracticeSequencerSequence)
        do {
            scheduleAndSequence = try await Task.detached(priority: .userInitiated) {
                let builder = PracticeSequencerSequenceBuilder()
                let schedule = builder.buildAudioEventSchedule(
                    timeline: timelineSnapshot,
                    tempoMap: tempoMapSnapshot,
                    startTick: tickRange.startTick,
                    initialSustainPedalDown: initialSustainPedalDown,
                    leadInSeconds: leadInSeconds,
                    endTick: tickRange.endTick
                )
                let sequence = try builder.buildSequence(from: schedule)
                return (schedule, sequence)
            }.value
        } catch {
            return
        }

        latestSchedule = scheduleAndSequence.schedule
        notifyStateChanged()

        do {
            try practiceSession.sequencerPlaybackService.load(sequence: scheduleAndSequence.sequence)
            try practiceSession.sequencerPlaybackService.play(fromSeconds: 0)
        } catch {
            return
        }
        didStartPlayback = true

        let sequenceEndSeconds = max(0, scheduleAndSequence.sequence.durationSeconds)
        while Task.isCancelled == false {
            guard isEnabled else { break }
            let nowSeconds = practiceSession.sequencerPlaybackService.currentSeconds()
            if nowSeconds >= sequenceEndSeconds {
                break
            }
            try? await Task.sleep(for: .milliseconds(33))
        }

        practiceSession.sequencerPlaybackService.stop()
        if isEnabled {
            _ = practiceSession.prepareAudioRecognitionSuppressWindowForPlayback()
            practiceSession.refreshAudioRecognitionForCurrentState()
        }
    }
}
