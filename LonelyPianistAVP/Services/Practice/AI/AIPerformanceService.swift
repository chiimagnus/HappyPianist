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
    var settingsProvider: any PracticeSessionSettingsProviderProtocol { get }

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
    private enum TriggerReason: String, Sendable {
        case shortPhrase = "short"
        case longPhrase = "long"
    }

    private enum ReplyPlan: Sendable {
        case schedule([PracticeSequencerMIDIEvent])
        case tickRange(startTick: Int, endTick: Int)
    }

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
    private let aiPlaybackServiceFactory: @MainActor () -> DuetAIPlaybackServiceFactory
    private let backendTimeout: Duration
    private let onStateChanged: @MainActor (State) -> Void

    private weak var practiceSession: (any AIPerformancePracticeSessionProtocol)?

    private var hasShutdown = false
    private var isEnabled = false
    private var lastKnownBackendKind: ImprovBackendKind?

    private var turnTakingCore = DuetTurnTakingCore()
    private var phraseEventBuffer = DuetPhraseEventBuffer()
    private var pendingSendTask: Task<Void, Never>?
    private var pendingSendReason: TriggerReason?
    private var inFlightGenerateTasks: [Int: Task<Void, Never>] = [:]
    private var nextGenerateSequenceID = 0
    private var nextPlaybackSequenceID = 0
    private var pendingReplyPlans: [Int: ReplyPlan] = [:]
    private var activationID = 0

    private var isGenerating = false
    private var isAIPlaybackActive = false
    private var latestSchedule: [PracticeSequencerMIDIEvent] = []
    private var lastImprovStatusText: String?

    @MainActor
    private lazy var aiPlaybackQueue: DuetAIPlaybackQueue = {
        DuetAIPlaybackQueue(
            logger: logger,
            playbackServiceFactory: aiPlaybackServiceFactory,
            onPlaybackActiveChanged: { [weak self] isActive in
                guard let self else { return }
                isAIPlaybackActive = isActive
                notifyStateChanged()
            }
        )
    }()

    init(
        logger: Logger,
        nowUptimeSeconds: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleepFor: @escaping @Sendable (Duration) async -> Void = { duration in try? await Task.sleep(for: duration) },
        discoveryOrchestrator: any ImprovBackendDiscoveryOrchestrating,
        backendRegistry: ImprovBackendRegistry,
        selectedBackendKind: @escaping @MainActor () -> ImprovBackendKind,
        aiPlaybackServiceFactory: @escaping @MainActor () -> DuetAIPlaybackServiceFactory,
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
        self.aiPlaybackServiceFactory = aiPlaybackServiceFactory
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
            pendingSendReason = nil

            for task in inFlightGenerateTasks.values {
                task.cancel()
            }
            inFlightGenerateTasks.removeAll(keepingCapacity: true)
            isGenerating = false
            isAIPlaybackActive = false
            nextGenerateSequenceID = 0
            nextPlaybackSequenceID = 0
            pendingReplyPlans.removeAll(keepingCapacity: true)

            turnTakingCore.reset()
            phraseEventBuffer.reset()
            lastImprovStatusText = nil
            latestSchedule = []
            notifyStateChanged()

            Task { [aiPlaybackQueue] in
                await aiPlaybackQueue.stopAll()
            }
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
            activationID += 1
            turnTakingCore.reset()
            phraseEventBuffer.reset()
            nextGenerateSequenceID = 0
            nextPlaybackSequenceID = 0
            pendingReplyPlans.removeAll(keepingCapacity: true)
            lastImprovStatusText = "AI 即兴：松手后约 0.6 秒触发（长句松手立即触发；播放期间也可继续触发）"
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
        case let .controlChange(controller, value):
            phraseEventBuffer.recordControlChange(
                controller: controller,
                value: value,
                timestampSeconds: event.receivedAtUptimeSeconds
            )
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
        case let .controlChange(controller, value32):
            phraseEventBuffer.recordControlChange(
                controller: controller,
                value: MIDI2ValueMapping.value32To7Bit(value32),
                timestampSeconds: event.receivedAtUptimeSeconds
            )
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
        practiceSession.refreshAudioRecognitionForCurrentState()
    }

    private func handleTurnTakingEvent(_ event: DuetTurnTakingCore.Event) {
        syncBackendDiscoveryIfNeeded()

        if case let .noteOn(_, _, timestampSeconds) = event {
            phraseEventBuffer.recordPhraseStartIfNeeded(timestampSeconds: timestampSeconds)
        }

        let decision = turnTakingCore.handle(event)
        switch decision {
        case .none:
            return
        case .cancelPendingSend:
            pendingSendTask?.cancel()
            pendingSendTask = nil
            pendingSendReason = nil
            logger.debug("turn-taking cancel pending send")
        case let .scheduleSend(deadlineTimestampSeconds):
            pendingSendTask?.cancel()
            pendingSendReason = .shortPhrase
            pendingSendTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let delaySeconds = max(0, deadlineTimestampSeconds - nowUptimeSeconds())
                logger.debug("turn-taking schedule send in \(delaySeconds, privacy: .public)s")
                await sleepFor(.seconds(delaySeconds))
                guard Task.isCancelled == false else { return }
                await triggerSendNow(reason: pendingSendReason ?? .shortPhrase)
            }
        case .sendNow:
            pendingSendTask?.cancel()
            pendingSendTask = nil
            pendingSendReason = .longPhrase
            logger.debug("turn-taking send now (long phrase)")
            Task { @MainActor [weak self] in
                await self?.triggerSendNow(reason: .longPhrase)
            }
        }
    }

    private func triggerSendNow(reason: TriggerReason) async {
        guard isEnabled else { return }
        guard let practiceSession else { return }
        guard practiceSession.autoplayState == .off else { return }
        guard practiceSession.isManualReplayPlaying == false else { return }

        let nowUptime = nowUptimeSeconds()
        let flushedPhrase = turnTakingCore.flushPhrase(endTimestampSeconds: nowUptime)
        let flushedCCEvents = phraseEventBuffer.flushPhrase(flushedPhrase: flushedPhrase)
        let policy = DuetPhrasePolicy.makeResult(from: flushedPhrase)
        guard policy.promptNotes.isEmpty == false else { return }

        let noteEvents = policy.promptNotes.map { note in
            ImprovEvent.note(note: note.note, velocity: note.velocity, time: note.time, duration: note.duration)
        }
        let promptEvents = (noteEvents + flushedCCEvents).sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            if lhs.type != rhs.type { return lhs.type == .cc }
            switch (lhs.type, rhs.type) {
            case (.cc, .cc):
                if (lhs.controller ?? 0) != (rhs.controller ?? 0) { return (lhs.controller ?? 0) < (rhs.controller ?? 0) }
                return (lhs.value ?? 0) < (rhs.value ?? 0)
            case (.note, .note):
                if (lhs.note ?? 0) != (rhs.note ?? 0) { return (lhs.note ?? 0) < (rhs.note ?? 0) }
                return (lhs.velocity ?? 0) < (rhs.velocity ?? 0)
            default:
                return false
            }
        }

        let maxTokens = max(1, Int((policy.desiredReplySeconds * 64.0).rounded()))
        let estimatedReplySeconds = estimatedBackendReplySeconds(maxTokens: maxTokens)
        let wasTrimmed = flushedPhrase.untrimmedEndTimeSeconds > 10 && abs(flushedPhrase.untrimmedEndTimeSeconds - flushedPhrase.endTimeSeconds) > 1e-9
        lastImprovStatusText = "即兴：prompt=\(formatSeconds(policy.promptEndTimeSeconds))s " +
            "replyWanted=\(formatSeconds(policy.desiredReplySeconds))s " +
            "replyMapped≈\(formatSeconds(estimatedReplySeconds))s"
        notifyStateChanged()

        let triggerLogMessage =
            "trigger send reason=\(reason.rawValue) " +
            "prompt=\(policy.promptEndTimeSeconds)s " +
            "untrimmed=\(flushedPhrase.untrimmedEndTimeSeconds)s " +
            "trimmed=\(flushedPhrase.endTimeSeconds)s " +
            "trim=\(wasTrimmed) " +
            "maxTokens=\(maxTokens)"
        logger.info("\(triggerLogMessage, privacy: .public)")

        let kind = selectedBackendKind()
        let sequenceID = nextGenerateSequenceID
        let activationAtSend = activationID
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

            logger.debug("improv generate start kind=\(kind.rawValue, privacy: .public) seq=\(sequenceID, privacy: .public)")
            await attemptSelectedBackendImprov(
                activationID: activationAtSend,
                sequenceID: sequenceID,
                kind: kind,
                promptEvents: promptEvents,
                maxTokens: maxTokens
            )
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
        activationID: Int,
        sequenceID: Int,
        kind: ImprovBackendKind,
        promptEvents: [ImprovEvent],
        maxTokens: Int
    ) async {
        guard isEnabled else { return }
        guard activationID == self.activationID else { return }
        guard practiceSession != nil else { return }
        guard let backend = backendRegistry.backend(for: kind) else {
            lastImprovStatusText = "Last improv: error(backendUnavailable \(kind.rawValue))"
            notifyStateChanged()
            return
        }

        // NOTE: The Python duet placeholder engine uses a fixed seed (0) when `seed == nil`,
        // which makes replies look "always the same melody" except for a global transposition.
        // Sending a per-turn seed keeps placeholder mode non-deterministic without affecting Magenta.
        let seed = UInt64(activationID) << 32 | UInt64(sequenceID)
        let params = ImprovGenerateParams(topP: 0.95, maxTokens: maxTokens, strategy: "model", seed: seed)
        let request = ImprovGenerateRequestV2(events: promptEvents, params: params, sessionID: improvSessionID)

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
            if let backendLatencyMS {
                logger.info("improv reply kind=\(kind.rawValue, privacy: .public) latencyMS=\(backendLatencyMS, privacy: .public)")
            } else {
                logger.info("improv reply kind=\(kind.rawValue, privacy: .public)")
            }
            await handleReplyPlan(.schedule(schedule), sequenceID: sequenceID, activationID: activationID)
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
            await handleReplyPlan(
                .tickRange(startTick: tickRange.startTick, endTick: tickRange.endTick),
                sequenceID: sequenceID,
                activationID: activationID
            )
            lastImprovStatusText = "Last improv: \(kind.rawValue)"
            notifyStateChanged()
        }
    }

    private func handleReplyPlan(_ plan: ReplyPlan, sequenceID: Int, activationID: Int) async {
        guard isEnabled else { return }
        guard activationID == self.activationID else {
            logger.debug("drop late reply plan seq=\(sequenceID, privacy: .public)")
            return
        }

        pendingReplyPlans[sequenceID] = plan
        while let next = pendingReplyPlans.removeValue(forKey: nextPlaybackSequenceID) {
            await enqueueReplyPlan(next)
            nextPlaybackSequenceID += 1
        }
    }

    private func enqueueReplyPlan(_ plan: ReplyPlan) async {
        switch plan {
        case let .schedule(schedule):
            await enqueueAIPlaybackSchedule(schedule)
        case let .tickRange(startTick, endTick):
            await enqueueAIPlaybackTickRange((startTick: startTick, endTick: endTick))
        }
    }

    private func enqueueAIPlaybackSchedule(_ schedule: [PracticeSequencerMIDIEvent]) async {
        guard let practiceSession else { return }
        let routing = practiceSession.settingsProvider.soundRoutingSettings
        let now = nowUptimeSeconds()
        let result = await aiPlaybackQueue.enqueue(schedule: schedule, routing: routing, enqueuedAtUptimeSeconds: now)
        latestSchedule = result.shiftedSchedule
        notifyStateChanged()

        let shiftedScheduleSnapshot = latestSchedule
        let noteOnCount = shiftedScheduleSnapshot.reduce(into: 0) { partialResult, event in
            if case .noteOn = event.kind { partialResult += 1 }
        }
        let firstNoteOn = shiftedScheduleSnapshot.first { event in
            if case .noteOn = event.kind { return true }
            return false
        }?.timeSeconds
        logger.info(
            "ai schedule shifted count=\(shiftedScheduleSnapshot.count, privacy: .public) noteOn=\(noteOnCount, privacy: .public) firstNoteOn=\(String(describing: firstNoteOn), privacy: .public) baseDelay=\(result.baseDelaySeconds, privacy: .public)"
        )

        let enqueueLogMessage =
            "ai enqueue baseDelay=\(result.baseDelaySeconds)s " +
            "queueCount=\(result.queueCount) " +
            "aiEnd=\(result.aiEndUptimeSeconds)"
        logger.info("\(enqueueLogMessage, privacy: .public)")
    }

    private func enqueueAIPlaybackTickRange(_ tickRange: (startTick: Int, endTick: Int)) async {
        guard let practiceSession else { return }

        let timelineSnapshot = practiceSession.autoplayTimeline
        let tempoMapSnapshot = practiceSession.tempoMap
        let initialSustainPedalDown = practiceSession.pedalTimeline?.isDown(atTick: tickRange.startTick) ?? false
        let leadInSeconds: TimeInterval = 0.05

        let schedule: [PracticeSequencerMIDIEvent]
        do {
            schedule = try await Task.detached(priority: .userInitiated) {
                PracticeSequencerSequenceBuilder().buildAudioEventSchedule(
                    timeline: timelineSnapshot,
                    tempoMap: tempoMapSnapshot,
                    startTick: tickRange.startTick,
                    initialSustainPedalDown: initialSustainPedalDown,
                    leadInSeconds: leadInSeconds,
                    endTick: tickRange.endTick
                )
            }.value
        } catch {
            return
        }

        let routing = practiceSession.settingsProvider.soundRoutingSettings
        let now = nowUptimeSeconds()
        let result = await aiPlaybackQueue.enqueue(schedule: schedule, routing: routing, enqueuedAtUptimeSeconds: now)
        latestSchedule = result.shiftedSchedule
        notifyStateChanged()
    }

    private func estimatedBackendReplySeconds(maxTokens: Int) -> TimeInterval {
        max(2.0, min(12.0, Double(maxTokens) / 64.0))
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        seconds.formatted(.number.precision(.fractionLength(2)))
    }
}
