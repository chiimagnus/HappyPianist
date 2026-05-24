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
        var isAIGenerating: Bool
        var isAIPlaybackActive: Bool
        var latestSchedule: [PracticeSequencerMIDIEvent]
        var lastImprovStatusText: String?
    }

    private let logger: Logger
    private let nowUptimeSeconds: () -> TimeInterval
    private let sleepFor: @Sendable (Duration) async -> Void
    private let improvSessionID: String
    private let discoveryOrchestrator: any ImprovBackendDiscoveryOrchestrating
    private let backendRegistry: ImprovBackendRegistry
    private let selectedBackendKind: @MainActor () -> ImprovBackendKind
    private let backendTimeout: Duration
    private let onStateChanged: @MainActor (State) -> Void

    private weak var practiceSession: (any AIPerformancePracticeSessionProtocol)?

    private var hasShutdown = false
    private var isEnabled = false
    private var lastKnownBackendKind: ImprovBackendKind?

    private var turnTakingCore = DuetTurnTakingCore()
    private var pendingSendTask: Task<Void, Never>?
    private var inFlightGenerateTasks: [Int: Task<Void, Never>] = [:]
    private var nextGenerateSequenceID = 0

    private var isGenerating = false
    private var isAIPlaybackActive = false
    private var latestSchedule: [PracticeSequencerMIDIEvent] = []
    private var lastImprovStatusText: String?

    init(
        logger: Logger,
        nowUptimeSeconds: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleepFor: @escaping @Sendable (Duration) async -> Void = { duration in try? await Task.sleep(for: duration) },
        discoveryOrchestrator: any ImprovBackendDiscoveryOrchestrating,
        backendRegistry: ImprovBackendRegistry,
        selectedBackendKind: @escaping @MainActor () -> ImprovBackendKind,
        backendTimeout: Duration = .seconds(12),
        onStateChanged: @escaping @MainActor (State) -> Void
    ) {
        self.logger = logger
        self.nowUptimeSeconds = nowUptimeSeconds
        self.sleepFor = sleepFor
        improvSessionID = UUID().uuidString
        self.discoveryOrchestrator = discoveryOrchestrator
        self.backendRegistry = backendRegistry
        self.selectedBackendKind = selectedBackendKind
        self.backendTimeout = backendTimeout
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
            guard isEnabled || pendingSendTask != nil || inFlightGenerateTasks.isEmpty == false else { return }

            isEnabled = false
            discoveryOrchestrator.stopAll()
            lastKnownBackendKind = nil

            pendingSendTask?.cancel()
            pendingSendTask = nil

            for task in inFlightGenerateTasks.values {
                task.cancel()
            }
            inFlightGenerateTasks.removeAll(keepingCapacity: true)
            isGenerating = false
            isAIPlaybackActive = false

            turnTakingCore.reset()
            lastImprovStatusText = nil
            latestSchedule = []
            notifyStateChanged()

            stopPlaybackAndRestoreAudioRecognitionIfNeeded()
            return
        }

        if isEnabled {
            return
        }

        let wasEnabled = isEnabled
        isEnabled = true

        syncBackendDiscoveryIfNeeded()

        if wasEnabled == false {
            turnTakingCore.reset()
            lastImprovStatusText = "AI 即兴：松手后约 0.6 秒触发（长句松手立即触发）"
            latestSchedule = []
            notifyStateChanged()
        }
    }

    func recordMIDI1EventForPhraseRecordingIfNeeded(_ event: MIDI1InputEvent) {
        guard isEnabled else { return }

        switch event.kind {
        case let .noteOn(note, velocity):
            handleTurnTakingEvent(.noteOn(note: note, velocity: velocity, timestampSeconds: event.receivedAtUptimeSeconds))
        case let .noteOff(note, _):
            handleTurnTakingEvent(.noteOff(note: note, timestampSeconds: event.receivedAtUptimeSeconds))
        default:
            return
        }
    }

    func recordMIDI2EventForPhraseRecordingIfNeeded(_ event: MIDI2InputEvent) {
        guard isEnabled else { return }

        switch event.kind {
        case let .noteOn(note, velocity16):
            handleTurnTakingEvent(
                .noteOn(
                    note: note,
                    velocity: MIDI2ValueMapping.value16To7Bit(velocity16),
                    timestampSeconds: event.receivedAtUptimeSeconds
                )
            )
        case let .noteOff(note, _):
            handleTurnTakingEvent(.noteOff(note: note, timestampSeconds: event.receivedAtUptimeSeconds))
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

        if keyContact.started.isEmpty == false {
            for note in keyContact.started {
                handleTurnTakingEvent(.noteOn(note: note, velocity: 90, timestampSeconds: nowUptimeSeconds))
            }
        }
        if keyContact.ended.isEmpty == false {
            for note in keyContact.ended {
                handleTurnTakingEvent(.noteOff(note: note, timestampSeconds: nowUptimeSeconds))
            }
        }
    }

    private func notifyStateChanged() {
        onStateChanged(
            State(
                isAIPerformanceActive: isGenerating || isAIPlaybackActive,
                isAIGenerating: isGenerating,
                isAIPlaybackActive: isAIPlaybackActive,
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

    private func handleTurnTakingEvent(_ event: DuetTurnTakingCore.Event) {
        syncBackendDiscoveryIfNeeded()

        let decision = turnTakingCore.handle(event)
        switch decision {
        case .none:
            return
        case .cancelPendingSend:
            pendingSendTask?.cancel()
            pendingSendTask = nil
        case let .scheduleSend(deadlineTimestampSeconds):
            pendingSendTask?.cancel()
            pendingSendTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let delaySeconds = max(0, deadlineTimestampSeconds - nowUptimeSeconds())
                await sleepFor(.seconds(delaySeconds))
                guard Task.isCancelled == false else { return }
                await triggerSendNow()
            }
        case .sendNow:
            pendingSendTask?.cancel()
            pendingSendTask = nil
            Task { @MainActor [weak self] in
                await self?.triggerSendNow()
            }
        }
    }

    private func triggerSendNow() async {
        guard isEnabled else { return }
        guard let practiceSession else { return }
        guard practiceSession.autoplayState == .off else { return }
        guard practiceSession.isManualReplayPlaying == false else { return }

        let nowUptime = nowUptimeSeconds()
        let flushedPhrase = turnTakingCore.flushPhrase(endTimestampSeconds: nowUptime)
        let policy = DuetPhrasePolicy.makeResult(from: flushedPhrase)
        guard policy.promptNotes.isEmpty == false else { return }

        let maxTokens = max(1, Int((policy.desiredReplySeconds * 64.0).rounded()))
        let estimatedReplySeconds = estimatedBackendReplySeconds(maxTokens: maxTokens)
        lastImprovStatusText = "即兴：prompt=\(formatSeconds(policy.promptEndTimeSeconds))s " +
            "replyWanted=\(formatSeconds(policy.desiredReplySeconds))s " +
            "replyMapped≈\(formatSeconds(estimatedReplySeconds))s"
        notifyStateChanged()

        let kind = selectedBackendKind()
        let sequenceID = nextGenerateSequenceID
        nextGenerateSequenceID += 1

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            isGenerating = true
            notifyStateChanged()
            defer {
                inFlightGenerateTasks.removeValue(forKey: sequenceID)
                isGenerating = inFlightGenerateTasks.isEmpty == false
                notifyStateChanged()
            }

            await attemptSelectedBackendImprov(kind: kind, promptNotes: policy.promptNotes, maxTokens: maxTokens)
        }
        inFlightGenerateTasks[sequenceID] = task
        isGenerating = true
        notifyStateChanged()
    }

    private func syncBackendDiscoveryIfNeeded() {
        let kind = selectedBackendKind()
        guard kind != lastKnownBackendKind else { return }
        lastKnownBackendKind = kind
        discoveryOrchestrator.start(for: kind)
    }

    private func attemptSelectedBackendImprov(
        kind: ImprovBackendKind,
        promptNotes: [ImprovDialogueNote],
        maxTokens: Int
    ) async {
        guard practiceSession != nil else { return }
        guard let backend = backendRegistry.backend(for: kind) else {
            lastImprovStatusText = "Last improv: error(backendUnavailable \(kind.rawValue))"
            notifyStateChanged()
            return
        }

        let params = ImprovGenerateParams(topP: 0.95, maxTokens: maxTokens, strategy: "model", seed: nil)
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
        case let .schedule(schedule, backendLatencyMS):
            await playAIPerformanceSchedule(schedule)
            if kind == .networkBonjourHTTPDuet, let backendLatencyMS {
                lastImprovStatusText = "上次生成耗时：\(backendLatencyMS)ms"
            } else {
                lastImprovStatusText = "Last improv: \(kind.rawValue)"
            }
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

    private func estimatedBackendReplySeconds(maxTokens: Int) -> TimeInterval {
        max(2.0, min(12.0, Double(maxTokens) / 64.0))
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        seconds.formatted(.number.precision(.fractionLength(2)))
    }

    private func playAIPerformanceSchedule(_ schedule: [PracticeSequencerMIDIEvent]) async {
        guard let practiceSession else { return }

        isAIPlaybackActive = true
        notifyStateChanged()

        practiceSession.stopVirtualPianoInput()
        practiceSession.sequencerPlaybackService.stop()
        practiceSession.stopAudioRecognition()
        latestSchedule = []
        notifyStateChanged()

        var didStartPlayback = false
        defer {
            isAIPlaybackActive = false
            if didStartPlayback == false {
                practiceSession.sequencerPlaybackService.stop()
                if isEnabled {
                    practiceSession.refreshAudioRecognitionForCurrentState()
                }
            }
            notifyStateChanged()
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

        isAIPlaybackActive = true
        notifyStateChanged()

        practiceSession.stopVirtualPianoInput()
        practiceSession.sequencerPlaybackService.stop()
        practiceSession.stopAudioRecognition()
        latestSchedule = []
        notifyStateChanged()

        var didStartPlayback = false
        defer {
            isAIPlaybackActive = false
            if didStartPlayback == false {
                practiceSession.sequencerPlaybackService.stop()
                if isEnabled {
                    practiceSession.refreshAudioRecognitionForCurrentState()
                }
            }
            notifyStateChanged()
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
