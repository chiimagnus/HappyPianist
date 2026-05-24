import Foundation
import ImprovProtocol
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
protocol ImprovBackendDiscoveryOrchestrating: AnyObject, Sendable {
    func start(for kind: ImprovBackendKind)
    func stopAll()
}

@MainActor
final class AIPerformanceService {
    struct State: Equatable {
        var isAIPerformanceActive: Bool
        var latestSchedule: [PracticeSequencerMIDIEvent]
        var lastImprovStatusText: String?
    }

    private let logger: Logger
    private let nowUptimeSeconds: () -> TimeInterval
    private let improvSessionID: String
    private let discoveryOrchestrator: any ImprovBackendDiscoveryOrchestrating
    private let backendRegistry: ImprovBackendRegistry
    private let selectedBackendKind: @MainActor () -> ImprovBackendKind
    private let backendTimeout: Duration
    private let pollInterval: Duration
    private let silenceTimeoutSeconds: TimeInterval
    private let onStateChanged: @MainActor (State) -> Void

    private weak var practiceSession: (any AIPerformancePracticeSessionProtocol)?

    private var hasShutdown = false
    private var isEnabled = false
    private var lastKnownBackendKind: ImprovBackendKind?

    private var silenceTrigger = NoteOnSilenceTrigger()
    private var phraseRecorder = PhraseRecorder()

    private var pollTask: Task<Void, Never>?

    private var isAIPerformanceActive = false
    private var latestSchedule: [PracticeSequencerMIDIEvent] = []
    private var lastImprovStatusText: String?

    init(
        logger: Logger,
        nowUptimeSeconds: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        discoveryOrchestrator: any ImprovBackendDiscoveryOrchestrating,
        backendRegistry: ImprovBackendRegistry,
        selectedBackendKind: @escaping @MainActor () -> ImprovBackendKind,
        backendTimeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(100),
        silenceTimeoutSeconds: TimeInterval = 2.0,
        onStateChanged: @escaping @MainActor (State) -> Void
    ) {
        self.logger = logger
        self.nowUptimeSeconds = nowUptimeSeconds
        improvSessionID = UUID().uuidString
        self.discoveryOrchestrator = discoveryOrchestrator
        self.backendRegistry = backendRegistry
        self.selectedBackendKind = selectedBackendKind
        self.backendTimeout = backendTimeout
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
            discoveryOrchestrator.stopAll()
            lastKnownBackendKind = nil
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

        syncBackendDiscoveryIfNeeded()

        if wasEnabled == false {
            silenceTrigger.reset()
            phraseRecorder.reset()
            lastImprovStatusText = "AI 即兴：等待你弹奏一句（停 2 秒触发）"
            latestSchedule = []
            notifyStateChanged()
        }

        guard pollTask == nil else { return }

        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while Task.isCancelled == false {
                guard isEnabled else { return }
                syncBackendDiscoveryIfNeeded()
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

        let promptNotes = phraseRecorder.flushPhrase(endTimestamp: nowUptime)
        let kind = selectedBackendKind()
        await attemptSelectedBackendImprov(kind: kind, promptNotes: promptNotes)
    }

    private func syncBackendDiscoveryIfNeeded() {
        let kind = selectedBackendKind()
        guard kind != lastKnownBackendKind else { return }
        lastKnownBackendKind = kind
        discoveryOrchestrator.start(for: kind)
    }

    private func attemptSelectedBackendImprov(kind: ImprovBackendKind, promptNotes: [ImprovDialogueNote]) async {
        guard practiceSession != nil else { return }
        guard let backend = backendRegistry.backend(for: kind) else {
            lastImprovStatusText = "Last improv: error(backendUnavailable \(kind.rawValue))"
            notifyStateChanged()
            return
        }

        let params = ImprovGenerateParams(topP: 0.95, maxTokens: 256, strategy: "model", seed: nil)
        let request = ImprovGenerateRequest(notes: promptNotes, params: params, sessionID: improvSessionID)

        let playbackPlan: ImprovBackendPlaybackPlan
        do {
            playbackPlan = try await backend.generatePlaybackPlan(request: request, timeout: backendTimeout)
        } catch {
            logger.warning("improv backend failed: \(String(describing: error), privacy: .public)")
            lastImprovStatusText = "Last improv: error(\(kind.rawValue) \(error.localizedDescription))"
            notifyStateChanged()
            return
        }

        switch playbackPlan {
        case let .schedule(schedule):
            await playAIPerformanceSchedule(schedule)
            lastImprovStatusText = "Last improv: \(kind.rawValue)"
            notifyStateChanged()
        case let .tickRange(maxMeasures):
            guard let tickRange = practiceSession?.aiPerformanceTickRange(maxMeasures: maxMeasures) else {
                lastImprovStatusText = "Last improv: error(\(kind.rawValue) noTickRange)"
                notifyStateChanged()
                return
            }
            await playAIPerformanceTickRange(tickRange)
            lastImprovStatusText = "Last improv: \(kind.rawValue)"
            notifyStateChanged()
        }
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
