import Foundation
import ImprovProtocol
import os

@MainActor
protocol AIPerformancePracticeSessionProtocol: AnyObject {
    var settingsProvider: any PracticeSessionSettingsProviderProtocol { get }

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

	private struct CandidateEvaluation {
		let shapedSchedule: [PracticeSequencerMIDIEvent]
		let assessment: DuetPhrasePolicy.QualityAssessment
	}

	private struct CandidateDiagnostics {
		let band: DuetPhrasePolicy.QualityAssessment.Band
		let candidateCount: Int
		let topRejectReason: DuetPhrasePolicy.QualityAssessment.Reason?
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

    private var noteContext = DuetPhraseBuffer()
    private var ccContext = DuetPhraseEventBuffer()
    private var controlEstimator = DuetTurnTakingCore()

    private var controlLoopTask: Task<Void, Never>?
    private var inFlightGenerateTasks: [Int: Task<Void, Never>] = [:]
    private var nextRequestID = 0
    private var activationID = 0
    private var lastWindowRequestTimestampSeconds: TimeInterval?

    private var isGenerating = false
    private var isAIPlaybackActive = false
    private var latestSchedule: [PracticeSequencerMIDIEvent] = []
    private var lastImprovStatusText: String?
    private var latestCandidateDiagnostics: CandidateDiagnostics?

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
        setEnabled(false)
        hasShutdown = true
    }

    func updatePracticeSession(_ session: any AIPerformancePracticeSessionProtocol) {
        if let practiceSession,
           ObjectIdentifier(practiceSession) != ObjectIdentifier(session),
           isEnabled {
            invalidateGeneration()
            noteContext.reset()
            ccContext.reset()
            controlEstimator.reset()
            latestSchedule = []
            latestCandidateDiagnostics = nil
            notifyStateChanged()
            Task { @MainActor [aiPlaybackQueue] in
                await aiPlaybackQueue.stopAll()
            }
        }
        practiceSession = session
    }

    func setEnabled(_ enabled: Bool) {
        guard hasShutdown == false else { return }

        if enabled == false {
            guard isEnabled || controlLoopTask != nil || inFlightGenerateTasks.isEmpty == false else { return }

            isEnabled = false
            activationID += 1
            controlLoopTask?.cancel()
            controlLoopTask = nil
            discoveryOrchestrator.stopAll()
            lastKnownBackendKind = nil

            for task in inFlightGenerateTasks.values {
                task.cancel()
            }
            inFlightGenerateTasks.removeAll(keepingCapacity: true)
            lastWindowRequestTimestampSeconds = nil
            isGenerating = false
            isAIPlaybackActive = false
            noteContext.reset()
            ccContext.reset()
            controlEstimator.reset()
            latestSchedule = []
            lastImprovStatusText = nil
            latestCandidateDiagnostics = nil
            notifyStateChanged()

            Task { @MainActor [weak self, aiPlaybackQueue] in
                await aiPlaybackQueue.stopAll()
                self?.stopPlaybackAndRestoreAudioRecognitionIfNeeded()
            }
            return
        }

        guard isEnabled == false else { return }
        isEnabled = true
        activationID += 1
        lastWindowRequestTimestampSeconds = nil
        noteContext.reset()
        ccContext.reset()
        controlEstimator.reset()
        latestSchedule = []
        lastImprovStatusText = "AI 即兴：连续共演模式已启用"
        latestCandidateDiagnostics = nil
        notifyStateChanged()
        syncBackendDiscoveryIfNeeded()
        startControlLoop()
    }

    func recordMIDI1EventForPhraseRecordingIfNeeded(_ event: MIDI1InputEvent) {
        guard isEnabled else { return }
        syncBackendDiscoveryIfNeeded()

        switch event.kind {
        case let .noteOn(note, velocity):
            noteContext.recordNoteOn(midi: note, velocity: velocity, timestampSeconds: event.receivedAtUptimeSeconds)
        case let .noteOff(note, _):
            noteContext.recordNoteOff(
                midi: note,
                timestampSeconds: event.receivedAtUptimeSeconds,
                sustainIsDown: ccContext.sustainValue >= 64
            )
        case let .controlChange(controller, value):
            let wasSustainDown = ccContext.sustainValue >= 64
            ccContext.recordControlChange(controller: controller, value: value, timestampSeconds: event.receivedAtUptimeSeconds)
            if controller == 64, wasSustainDown, value < 64 {
                noteContext.releaseSustainedNotes(timestampSeconds: event.receivedAtUptimeSeconds)
            }
        default:
            return
        }
    }

    func recordMIDI2EventForPhraseRecordingIfNeeded(_ event: MIDI2InputEvent) {
        guard isEnabled else { return }
        syncBackendDiscoveryIfNeeded()

        switch event.kind {
        case let .noteOn(note, velocity16):
            noteContext.recordNoteOn(
                midi: note,
                velocity: MIDI2ValueMapping.value16To7Bit(velocity16),
                timestampSeconds: event.receivedAtUptimeSeconds
            )
        case let .noteOff(note, _):
            noteContext.recordNoteOff(
                midi: note,
                timestampSeconds: event.receivedAtUptimeSeconds,
                sustainIsDown: ccContext.sustainValue >= 64
            )
        case let .controlChange(controller, value32):
            let value = MIDI2ValueMapping.value32To7Bit(value32)
            let wasSustainDown = ccContext.sustainValue >= 64
            ccContext.recordControlChange(
                controller: controller,
                value: value,
                timestampSeconds: event.receivedAtUptimeSeconds
            )
            if controller == 64, wasSustainDown, value < 64 {
                noteContext.releaseSustainedNotes(timestampSeconds: event.receivedAtUptimeSeconds)
            }
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
        syncBackendDiscoveryIfNeeded()

        guard keyContact.started.isEmpty == false || keyContact.ended.isEmpty == false else { return }

        for note in keyContact.started {
            noteContext.recordNoteOn(midi: note, velocity: 90, timestampSeconds: nowUptimeSeconds)
        }
        for note in keyContact.ended {
            noteContext.recordNoteOff(midi: note, timestampSeconds: nowUptimeSeconds, sustainIsDown: false)
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
        practiceSession?.refreshAudioRecognitionForCurrentState()
    }

    private func controlDecision(
        noteSnapshot: DuetPhraseBuffer.Snapshot,
        ccSnapshot: DuetPhraseEventBuffer.Snapshot
    ) -> DuetTurnTakingCore.Decision {
        controlEstimator.evaluate(
            .init(
                nowTimestampSeconds: noteSnapshot.nowTimestampSeconds,
                heldNotesCount: noteSnapshot.heldNotes.count,
                sustainValue: ccSnapshot.sustainValue,
                recentIOIMedianSeconds: noteSnapshot.recentIOIMedianSeconds,
                recentVelocityTrend: noteSnapshot.recentVelocityTrend,
                recentNoteDensityPerSecond: noteSnapshot.recentNoteDensityPerSecond,
                lastUserEventTimestampSeconds: noteSnapshot.lastUserEventTimestampSeconds,
                lastNoteOnTimestampSeconds: noteSnapshot.lastNoteOnTimestampSeconds,
                activePitchCenter: noteSnapshot.activePitchCenter
            )
        )
    }

    private func startControlLoop() {
        controlLoopTask?.cancel()
        controlLoopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while Task.isCancelled == false, isEnabled {
                await runContinuousControlTick()
                await sleepFor(.milliseconds(100))
                await Task.yield()
            }
        }
    }

    private func runContinuousControlTick() async {
        guard isEnabled else { return }
        guard practiceSession != nil else { return }

        syncBackendDiscoveryIfNeeded()

        let now = nowUptimeSeconds()
        let bootstrapPolicy = DuetPhrasePolicy.RequestPolicy(
            lookbackSeconds: 4.0,
            maxPromptSeconds: 3.0,
            requestWindowSeconds: 0.6,
            minRequestIntervalSeconds: 0.22,
            maxTokens: 36
        )
        let noteSnapshot = noteContext.snapshot(
            nowTimestampSeconds: now,
            lookbackSeconds: bootstrapPolicy.lookbackSeconds,
            maxPromptSeconds: bootstrapPolicy.maxPromptSeconds
        )
        let ccSnapshot = ccContext.snapshot(
            nowTimestampSeconds: now,
            lookbackSeconds: bootstrapPolicy.lookbackSeconds,
            maxPromptSeconds: bootstrapPolicy.maxPromptSeconds
        )
        let decision = controlDecision(noteSnapshot: noteSnapshot, ccSnapshot: ccSnapshot)

        if decision.shouldClearFutureWindows {
            await aiPlaybackQueue.clearPendingWindow()
            if isAIPlaybackActive == false {
                latestSchedule = []
            }
        }

        if shouldRequestWindow(nowTimestampSeconds: now, decision: decision, noteSnapshot: noteSnapshot) {
            let requestPolicy = DuetPhrasePolicy.requestPolicy(for: decision)
            let promptEvents = DuetPhrasePolicy.buildPromptEvents(
                noteSnapshot: noteSnapshot,
                ccSnapshot: ccSnapshot,
                policy: requestPolicy
            )
            if promptEvents.contains(where: { $0.type == .note }) {
                await requestContinuousWindow(
                    nowTimestampSeconds: now,
                    promptEvents: promptEvents,
                    requestPolicy: requestPolicy
                )
            }
        }

        lastImprovStatusText = makeStatusText(decision: decision, noteSnapshot: noteSnapshot)
        notifyStateChanged()
    }

    private func shouldRequestWindow(
        nowTimestampSeconds: TimeInterval,
        decision: DuetTurnTakingCore.Decision,
        noteSnapshot: DuetPhraseBuffer.Snapshot
    ) -> Bool {
        guard decision.shouldRequestGeneration else { return false }
        guard noteSnapshot.lastUserEventTimestampSeconds != nil else { return false }
        guard inFlightGenerateTasks.isEmpty else { return false }

        if let lastWindowRequestTimestampSeconds,
           nowTimestampSeconds - lastWindowRequestTimestampSeconds < decision.minRequestIntervalSeconds {
            return false
        }
        return true
    }

    private func requestContinuousWindow(
        nowTimestampSeconds: TimeInterval,
        promptEvents: [ImprovEvent],
        requestPolicy: DuetPhrasePolicy.RequestPolicy
    ) async {
        let kind = selectedBackendKind()
        let requestID = nextRequestID
        let activationAtRequest = activationID
        nextRequestID += 1
        lastWindowRequestTimestampSeconds = nowTimestampSeconds

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            isGenerating = true
            notifyStateChanged()
            defer {
                inFlightGenerateTasks.removeValue(forKey: requestID)
                isGenerating = inFlightGenerateTasks.isEmpty == false
                notifyStateChanged()
            }

            await generateContinuousWindow(
                requestID: requestID,
                activationAtRequest: activationAtRequest,
                kind: kind,
                promptEvents: promptEvents,
                requestPolicy: requestPolicy
            )
        }
        inFlightGenerateTasks[requestID] = task
        isGenerating = true
        notifyStateChanged()
    }

	private func generateContinuousWindow(
		requestID: Int,
		activationAtRequest: Int,
		kind: ImprovBackendKind,
		promptEvents: [ImprovEvent],
        requestPolicy: DuetPhrasePolicy.RequestPolicy
    ) async {
        guard isEnabled else { return }
        guard activationAtRequest == activationID else { return }
        guard kind == selectedBackendKind() else { return }
        guard let practiceSession else { return }
        guard let backend = backendRegistry.backend(for: kind) else {
            lastImprovStatusText = "AI 即兴：后端不可用（\(kind.rawValue)）"
            notifyStateChanged()
            return
        }

		let seed = UInt64(activationAtRequest) << 32 | UInt64(requestID)

		let rawCandidates: [[PracticeSequencerMIDIEvent]]
		do {
			rawCandidates = try await generatePlaybackCandidates(
				backend: backend,
				kind: kind,
				promptEvents: promptEvents,
				requestPolicy: requestPolicy,
				baseSeed: seed
			)
        } catch {
			guard isEnabled, activationAtRequest == activationID, kind == selectedBackendKind() else { return }
            logger.warning("continuous duet backend failed: \(String(describing: error), privacy: .public)")
            lastImprovStatusText = "AI 即兴：生成失败（\(kind.rawValue)）"
            notifyStateChanged()
            return
        }

        guard isEnabled else { return }
        guard activationAtRequest == activationID else { return }
		guard kind == selectedBackendKind() else { return }

        let now = nowUptimeSeconds()
        let noteSnapshot = noteContext.snapshot(
            nowTimestampSeconds: now,
            lookbackSeconds: requestPolicy.lookbackSeconds,
            maxPromptSeconds: requestPolicy.maxPromptSeconds
        )
		let ccSnapshot = ccContext.snapshot(
			nowTimestampSeconds: now,
			lookbackSeconds: requestPolicy.lookbackSeconds,
			maxPromptSeconds: requestPolicy.maxPromptSeconds
		)
		let decision = controlDecision(noteSnapshot: noteSnapshot, ccSnapshot: ccSnapshot)
		guard decision.shouldRequestGeneration else { return }
		let responsePolicy = DuetPhrasePolicy.requestPolicy(for: decision)
		let evaluations = rawCandidates.map {
			evaluateCandidate(
				rawSchedule: $0,
				noteSnapshot: noteSnapshot,
				controlMode: decision.mode,
				horizonSeconds: responsePolicy.requestWindowSeconds
			)
		}
		let topRejectReason = evaluations
			.filter { $0.assessment.band == .reject }
			.compactMap(\.assessment.primaryReason)
			.first
		guard let bestCandidate = selectBestCandidate(from: evaluations) else {
			latestCandidateDiagnostics = CandidateDiagnostics(band: .reject, candidateCount: evaluations.count, topRejectReason: topRejectReason)
			lastImprovStatusText = makeStatusText(decision: decision, noteSnapshot: noteSnapshot)
			notifyStateChanged()
			return
		}
		let shapedSchedule = bestCandidate.shapedSchedule
        guard shapedSchedule.isEmpty == false else { return }

        let result = await aiPlaybackQueue.submitWindow(
            schedule: shapedSchedule,
            routing: practiceSession.settingsProvider.soundRoutingSettings,
            submittedAtUptimeSeconds: now
        )
        latestSchedule = result.shiftedSchedule
		latestCandidateDiagnostics = CandidateDiagnostics(
			band: bestCandidate.assessment.band,
			candidateCount: evaluations.count,
			topRejectReason: topRejectReason
		)
		lastImprovStatusText = makeStatusText(decision: decision, noteSnapshot: noteSnapshot)
        notifyStateChanged()
    }

	private func generatePlaybackCandidates(
		backend: any ImprovBackendProtocol,
		kind: ImprovBackendKind,
		promptEvents: [ImprovEvent],
		requestPolicy: DuetPhrasePolicy.RequestPolicy,
		baseSeed: UInt64
	) async throws -> [[PracticeSequencerMIDIEvent]] {
		let candidateCount = preferredCandidateCount(for: kind)
		var candidates: [[PracticeSequencerMIDIEvent]] = []
		var firstError: (any Error)?
		candidates.reserveCapacity(candidateCount)

		for candidateIndex in 0 ..< candidateCount {
			let request = makeGenerateRequest(
				promptEvents: promptEvents,
				requestPolicy: requestPolicy,
				seed: candidateSeed(baseSeed: baseSeed, candidateIndex: candidateIndex)
			)
			do {
				let playbackPlan = try await backend.generatePlaybackPlan(request: request, timeout: backendTimeout)
				if case let .schedule(schedule, _) = playbackPlan {
					candidates.append(schedule)
				}
			} catch {
				if candidateCount == 1 { throw error }
				if firstError == nil { firstError = error }
			}
		}

		if candidates.isEmpty, let firstError { throw firstError }
		return candidates
	}

	private func preferredCandidateCount(for kind: ImprovBackendKind) -> Int {
		switch kind {
		case .localRule:
			return 3
		case .networkBonjourHTTPAriaV2, .networkBonjourWebSocketAriaV2, .localCoreMLDuet:
			return 1
		}
	}

	private func makeGenerateRequest(
		promptEvents: [ImprovEvent],
		requestPolicy: DuetPhrasePolicy.RequestPolicy,
		seed: UInt64
	) -> ImprovGenerateRequestV2 {
		ImprovGenerateRequestV2(
			events: promptEvents,
			params: ImprovGenerateParams(
				topP: 0.95,
				maxTokens: max(1, requestPolicy.maxTokens),
				strategy: "continuous",
				seed: seed
			),
			sessionID: improvSessionID
		)
	}

	private func candidateSeed(baseSeed: UInt64, candidateIndex: Int) -> UInt64 {
		guard candidateIndex > 0 else { return baseSeed }
		return baseSeed &+ (UInt64(candidateIndex) &* 0x9E3779B97F4A7C15)
	}

	private func evaluateCandidate(
		rawSchedule: [PracticeSequencerMIDIEvent],
		noteSnapshot: DuetPhraseBuffer.Snapshot,
		controlMode: DuetTurnTakingCore.Mode,
		horizonSeconds: TimeInterval
	) -> CandidateEvaluation {
		let rawAssessment = DuetPhrasePolicy.assessSchedule(
			rawSchedule,
			noteSnapshot: noteSnapshot,
			horizonSeconds: horizonSeconds
		)
		let shapedSchedule = DuetPhrasePolicy.shapeSchedule(
			rawSchedule,
			noteSnapshot: noteSnapshot,
			controlMode: controlMode,
			horizonSeconds: horizonSeconds
		)
		let assessment: DuetPhrasePolicy.QualityAssessment
		if shapedSchedule.isEmpty {
			assessment = rawAssessment.band == .reject
				? rawAssessment
				: .init(
					band: .reject,
					score: rawAssessment.score,
					reasons: rawAssessment.reasons.isEmpty ? [.fragmentedWindow] : rawAssessment.reasons,
					noteOnCount: rawAssessment.noteOnCount,
					effectiveDurationSeconds: rawAssessment.effectiveDurationSeconds
				)
		} else {
			assessment = DuetPhrasePolicy.assessSchedule(
				shapedSchedule,
				noteSnapshot: noteSnapshot,
				horizonSeconds: horizonSeconds
			)
		}
		return CandidateEvaluation(shapedSchedule: shapedSchedule, assessment: assessment)
	}

	private func selectBestCandidate(from evaluations: [CandidateEvaluation]) -> CandidateEvaluation? {
		evaluations
			.filter { $0.shapedSchedule.isEmpty == false && $0.assessment.band != .reject }
			.max { lhs, rhs in
				if bandRank(lhs.assessment.band) != bandRank(rhs.assessment.band) {
					return bandRank(lhs.assessment.band) < bandRank(rhs.assessment.band)
				}
				if lhs.assessment.score != rhs.assessment.score {
					return lhs.assessment.score < rhs.assessment.score
				}
				return lhs.assessment.noteOnCount < rhs.assessment.noteOnCount
			}
	}

	private func bandRank(_ band: DuetPhrasePolicy.QualityAssessment.Band) -> Int {
		switch band {
		case .acceptable:
			return 2
		case .risky:
			return 1
		case .reject:
			return 0
		}
	}

    private func syncBackendDiscoveryIfNeeded() {
        let kind = selectedBackendKind()
        guard kind != lastKnownBackendKind else { return }
        if lastKnownBackendKind != nil, isEnabled {
            invalidateGeneration()
            Task { [aiPlaybackQueue] in
                await aiPlaybackQueue.clearPendingWindow()
            }
        }
        lastKnownBackendKind = kind
        discoveryOrchestrator.start(for: kind)
    }

    private func invalidateGeneration() {
        activationID &+= 1
        for task in inFlightGenerateTasks.values {
            task.cancel()
        }
        inFlightGenerateTasks.removeAll(keepingCapacity: true)
        lastWindowRequestTimestampSeconds = nil
        isGenerating = false
        latestCandidateDiagnostics = nil
        notifyStateChanged()
    }

    private func makeStatusText(
        decision: DuetTurnTakingCore.Decision,
        noteSnapshot: DuetPhraseBuffer.Snapshot
    ) -> String {
        let density = noteSnapshot.recentNoteDensityPerSecond.formatted(.number.precision(.fractionLength(2)))
        let ioiText = noteSnapshot.recentIOIMedianSeconds.map(formatSeconds) ?? "-"
        let generationText = isGenerating ? "生成中" : "监听中"
        let cadence = formatSeconds(decision.minRequestIntervalSeconds)
        let horizon = formatSeconds(decision.requestWindowSeconds)
        let diagnostics = latestCandidateDiagnostics.map { diagnostics in
            let reason = diagnostics.topRejectReason.map { " · topReject=\($0.rawValue)" } ?? ""
            return " · q=\(diagnostics.band.rawValue) · candidates=\(diagnostics.candidateCount)\(reason)"
        } ?? ""
        return "AI 即兴：\(generationText) · mode=\(decision.mode.rawValue) · held=\(noteSnapshot.heldNotes.count) · density=\(density)/s · ioi=\(ioiText)s · cadence=\(cadence)s · window=\(horizon)s\(diagnostics)"
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        seconds.formatted(.number.precision(.fractionLength(2)))
    }
}
