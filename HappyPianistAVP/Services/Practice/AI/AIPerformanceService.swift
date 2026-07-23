import Foundation

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
        let responseQualityAssessment: ImprovQualityRubric.Assessment
        let responseLatencyBucket: PianoPerformanceDurationBucket?

        var qualityGateReason: String? {
            assessment.primaryReason?.rawValue ?? responseQualityAssessment.reasons.first?.rawValue
        }
    }

    private struct CandidateDiagnostics {
        let band: DuetPhrasePolicy.QualityAssessment.Band
        let candidateCount: Int
        let topRejectReason: DuetPhrasePolicy.QualityAssessment.Reason?
    }

    private enum GenerationFailureCategory: String {
        case invalidSelection = "invalid_selection"
        case unavailable
        case timeout
        case invalidResponse = "invalid_response"
        case qualityGate = "quality_gate"
        case failed

        var statusText: String {
            switch self {
            case .invalidSelection:
                "后端选择无效"
            case .unavailable:
                "后端不可用"
            case .timeout:
                "生成超时"
            case .invalidResponse:
                "响应无效"
            case .qualityGate:
                "质量门拒绝"
            case .failed:
                "生成失败"
            }
        }
    }

    private enum GenerationDiscardOutcome: String {
        case cancelled
        case staleDisabled = "stale_disabled"
        case staleActivation = "stale_activation"
        case stalePhrase = "stale_phrase"
        case staleBackend = "stale_backend"
        case stalePlayback = "stale_playback"
    }

    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let nowUptimeSeconds: () -> TimeInterval
    private let sleepFor: @Sendable (Duration) async -> Void
    private let improvSessionID: String
    private let discoveryOrchestrator: any ImprovBackendDiscoveryOrchestrating
    private let backendRegistry: ImprovBackendRegistry
    private let selectedBackendKind: @MainActor () -> ImprovBackendKind?
    private let aiPlaybackServiceFactory: @MainActor () -> DuetAIPlaybackServiceFactory
    private let backendTimeout: Duration
    private let onStateChanged: @MainActor (State) -> Void

    private weak var practiceSession: (any AIPerformancePracticeSessionProtocol)?

    private var hasShutdown = false
    private var isEnabled = false
    private var lastKnownBackendKind: ImprovBackendKind?

    private var noteContext = DuetPhraseBuffer()
    private var ccContext = DuetPhraseEventBuffer()
    private var activeKeyContactIDsByMIDINote: [Int: Set<PianoKeyContactID>] = [:]
    private var midiObservationAdapter = MIDIPerformanceObservationAdapter()
    private let keyContactObservationAdapter = PianoKeyContactPerformanceObservationAdapter()
    private let phraseObservationAdapter = PerformanceObservationPhraseAdapter()
    private var controlEstimator = DuetTurnTakingCore()

    private var controlLoopTask: Task<Void, Never>?
    private var inFlightGenerateTasks: [Int: Task<Void, Never>] = [:]
    private var nextRequestID = 0
    private var activationID = 0
    private var phraseGeneration = 0
    private var lastWindowRequestTimestampSeconds: TimeInterval?

    private var isGenerating = false
    private var isAIPlaybackActive = false
    private var latestSchedule: [PracticeSequencerMIDIEvent] = []
    private var lastImprovStatusText: String?
    private var generationFailureStatusText: String?
    private var latestCandidateDiagnostics: CandidateDiagnostics?

    @MainActor
    private lazy var aiPlaybackQueue: DuetAIPlaybackQueue = .init(
        diagnosticsReporter: diagnosticsReporter,
        playbackServiceFactory: aiPlaybackServiceFactory,
        onPlaybackActiveChanged: { [weak self] isActive in
            guard let self else { return }
            isAIPlaybackActive = isActive
            notifyStateChanged()
        }
    )

    init(
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        nowUptimeSeconds: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleepFor: @escaping @Sendable (Duration) async -> Void = { duration in try? await Task.sleep(for: duration) },
        discoveryOrchestrator: any ImprovBackendDiscoveryOrchestrating,
        backendRegistry: ImprovBackendRegistry,
        selectedBackendKind: @escaping @MainActor () -> ImprovBackendKind?,
        aiPlaybackServiceFactory: @escaping @MainActor () -> DuetAIPlaybackServiceFactory,
        backendTimeout: Duration = .seconds(12),
        onStateChanged: @escaping @MainActor (State) -> Void
    ) {
        self.diagnosticsReporter = diagnosticsReporter
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
           isEnabled
        {
            let invalidatedPhraseGeneration = invalidateGeneration()
            resetPhraseInput()
            controlEstimator.reset()
            latestSchedule = []
            latestCandidateDiagnostics = nil
            notifyStateChanged()
            Task { @MainActor [aiPlaybackQueue] in
                await aiPlaybackQueue.stopAll(rejectingThrough: invalidatedPhraseGeneration)
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
            let invalidatedPhraseGeneration = invalidatePhraseGeneration()
            controlLoopTask?.cancel()
            controlLoopTask = nil
            discoveryOrchestrator.stopAll()
            lastKnownBackendKind = nil

            isAIPlaybackActive = false
            resetPhraseInput()
            controlEstimator.reset()
            latestSchedule = []
            lastImprovStatusText = nil
            generationFailureStatusText = nil
            latestCandidateDiagnostics = nil
            notifyStateChanged()

            Task { @MainActor [weak self, aiPlaybackQueue] in
                await aiPlaybackQueue.stopAll(rejectingThrough: invalidatedPhraseGeneration)
                self?.stopPlaybackAndRestoreAudioRecognitionIfNeeded()
            }
            return
        }

        guard isEnabled == false else { return }
        isEnabled = true
        activationID += 1
        _ = invalidatePhraseGeneration()
        resetPhraseInput()
        controlEstimator.reset()
        latestSchedule = []
        lastImprovStatusText = "AI 即兴：连续共演模式已启用"
        generationFailureStatusText = nil
        latestCandidateDiagnostics = nil
        notifyStateChanged()
        _ = syncBackendDiscoveryIfNeeded()
        startControlLoop()
    }

    func recordMIDI1EventForPhraseRecordingIfNeeded(_ event: MIDI1InputEvent) {
        recordPerformanceObservationForPhraseRecordingIfNeeded(
            midiObservationAdapter.observation(
                for: event,
                generation: UInt64(max(0, activationID))
            )
        )
    }

    func recordMIDI2EventForPhraseRecordingIfNeeded(_ event: MIDI2InputEvent) {
        recordPerformanceObservationForPhraseRecordingIfNeeded(
            midiObservationAdapter.observation(
                for: event,
                generation: UInt64(max(0, activationID))
            )
        )
    }

    func recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: Bool,
        isVirtualPianoEnabled: Bool = false,
        observations: [PianoKeyContactObservation]
    ) {
        guard usesBluetoothMIDIInput == false else { return }
        guard isEnabled else { return }
        guard syncBackendDiscoveryIfNeeded() else { return }

        let sourceKind: PerformanceObservation.Source.Kind = isVirtualPianoEnabled
            ? .virtualPianoContact
            : .realPianoContact
        let generation = UInt64(max(0, activationID))

        for contact in observations {
            guard let note = contact.keyCandidate.exactMIDINote else { continue }
            switch contact.phase {
            case .started:
                var activeContactIDs = activeKeyContactIDsByMIDINote[note, default: []]
                let shouldRecordNoteOn = activeContactIDs.isEmpty
                guard activeContactIDs.insert(contact.id).inserted else { continue }
                activeKeyContactIDsByMIDINote[note] = activeContactIDs
                guard shouldRecordNoteOn else { continue }
                recordPerformanceObservationForPhraseRecordingIfNeeded(
                    keyContactObservationAdapter.observation(
                        from: contact,
                        sourceKind: sourceKind,
                        generation: generation
                    )
                )
            case .ended:
                guard var activeContactIDs = activeKeyContactIDsByMIDINote[note],
                      activeContactIDs.remove(contact.id) != nil
                else { continue }
                guard activeContactIDs.isEmpty else {
                    activeKeyContactIDsByMIDINote[note] = activeContactIDs
                    continue
                }
                activeKeyContactIDsByMIDINote.removeValue(forKey: note)
                recordPerformanceObservationForPhraseRecordingIfNeeded(
                    keyContactObservationAdapter.observation(
                        from: contact,
                        sourceKind: sourceKind,
                        generation: generation
                    )
                )
            case .held:
                break
            }
        }
    }

    func recordPerformanceObservationForPhraseRecordingIfNeeded(_ observation: PerformanceObservation) {
        guard isEnabled, observation.source.role == .userPerformance else { return }
        guard syncBackendDiscoveryIfNeeded() else { return }
        recordPhraseObservation(observation)
    }

    private func recordPhraseObservation(_ observation: PerformanceObservation) {
        guard observation.source.role == .userPerformance,
              let event = phraseObservationAdapter.phraseEvent(from: observation)
        else { return }
        let invalidatedPhraseGeneration = invalidatePhraseGeneration()
        Task { [aiPlaybackQueue] in
            await aiPlaybackQueue.invalidatePendingWindows(through: invalidatedPhraseGeneration)
        }
        recordPhraseEvent(event)
        notifyStateChanged()
    }

    private func recordPhraseEvent(_ event: PerformanceObservationPhraseAdapter.PhraseEvent) {
        switch event.kind {
        case .noteOn, .noteOff:
            noteContext.record(event, sustainIsDown: ccContext.sustainValue >= 64)
        case let .controlChange(controller, value):
            let wasSustainDown = ccContext.sustainValue >= 64
            ccContext.record(event)
            if controller == 64, wasSustainDown, value < 64 {
                noteContext.releaseSustainedNotes(timestampSeconds: event.timestamp.seconds)
            }
        case .allNotesOff:
            clearPhraseContext()
        }
    }

    private func resetPhraseInput() {
        clearPhraseContext()
        midiObservationAdapter.resetClockCalibration()
    }

    private func clearPhraseContext() {
        noteContext.reset()
        ccContext.reset()
        activeKeyContactIDsByMIDINote.removeAll(keepingCapacity: true)
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
        scheduleNextControlTick()
    }

    private func scheduleNextControlTick() {
        controlLoopTask = Task { @MainActor [weak self] in
            guard let self, self.isEnabled else { return }
            await self.runContinuousControlTick()
            await self.sleepFor(.milliseconds(100))
            // ponytail: injected clocks may return immediately; prevent a MainActor hot loop.
            try? await Task.sleep(for: .milliseconds(1))
            guard Task.isCancelled == false, self.isEnabled else { return }
            self.scheduleNextControlTick()
        }
    }

    private func runContinuousControlTick() async {
        guard isEnabled else { return }
        guard practiceSession != nil else { return }

        guard syncBackendDiscoveryIfNeeded() else { return }

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
            let phrase = CreativeDuetPhrase(
                events: promptEvents,
                provenance: noteSnapshot.phraseProvenance.merging(ccSnapshot.phraseProvenance)
            )
            if phrase.events.contains(where: { $0.type == .note }) {
                await requestContinuousWindow(
                    nowTimestampSeconds: now,
                    phrase: phrase,
                    requestPolicy: requestPolicy
                )
            }
        }

        lastImprovStatusText = generationFailureStatusText ?? makeStatusText(decision: decision, noteSnapshot: noteSnapshot)
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
           nowTimestampSeconds - lastWindowRequestTimestampSeconds < decision.minRequestIntervalSeconds
        {
            return false
        }
        return true
    }

    private func requestContinuousWindow(
        nowTimestampSeconds: TimeInterval,
        phrase: CreativeDuetPhrase,
        requestPolicy: DuetPhrasePolicy.RequestPolicy
    ) async {
        guard let kind = selectedBackendKind() else {
            reportGenerationFailure(provider: nil, category: .invalidSelection)
            return
        }
        generationFailureStatusText = nil
        let requestID = nextRequestID
        let activationAtRequest = activationID
        let phraseGenerationAtRequest = phraseGeneration
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
                phraseGenerationAtRequest: phraseGenerationAtRequest,
                kind: kind,
                phrase: phrase,
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
        phraseGenerationAtRequest: Int,
        kind: ImprovBackendKind,
        phrase: CreativeDuetPhrase,
        requestPolicy: DuetPhrasePolicy.RequestPolicy
    ) async {
        guard isEnabled else { return }
        guard activationAtRequest == activationID else { return }
        guard phraseGenerationAtRequest == phraseGeneration else { return }
        guard selectedBackendKind() == kind else { return }
        guard let practiceSession else { return }
        let backend: any ImprovBackendProtocol
        do {
            backend = try backendRegistry.backend(for: kind)
        } catch {
            reportGenerationFailure(provider: kind, category: failureCategory(for: error))
            return
        }

        let seed = UInt64(activationAtRequest) << 32 | UInt64(requestID)

        let responses: [CreativeDuetResponse]
        do {
            responses = try await generateCreativeResponses(
                backend: backend,
                kind: kind,
                phrase: phrase,
                requestPolicy: requestPolicy,
                baseSeed: seed,
                requestID: requestID,
                activationID: activationAtRequest
            )
        } catch is CancellationError {
            reportGenerationDiscard(provider: kind, outcome: .cancelled)
            return
        } catch {
            if let outcome = staleGenerationOutcome(
                activationAtRequest: activationAtRequest,
                phraseGenerationAtRequest: phraseGenerationAtRequest,
                kind: kind
            ) {
                reportGenerationDiscard(provider: kind, outcome: outcome)
                return
            }
            reportGenerationFailure(provider: kind, category: failureCategory(for: error))
            return
        }

        if let outcome = staleGenerationOutcome(
            activationAtRequest: activationAtRequest,
            phraseGenerationAtRequest: phraseGenerationAtRequest,
            kind: kind
        ) {
            reportGenerationDiscard(provider: kind, outcome: outcome)
            return
        }

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
        let evaluations = responses.map {
            evaluateCandidate(
                response: $0,
                noteSnapshot: noteSnapshot,
                controlMode: decision.mode,
                horizonSeconds: responsePolicy.requestWindowSeconds
            )
        }
        let topRejectReason = evaluations
            .filter { $0.assessment.band == .reject }
            .compactMap(\.assessment.primaryReason)
            .first
        let rejectedCandidate = evaluations.first {
            $0.assessment.band == .reject || $0.responseQualityAssessment.isUsable == false
        }
        guard let bestCandidate = selectBestCandidate(from: evaluations) else {
            latestCandidateDiagnostics = CandidateDiagnostics(band: .reject, candidateCount: evaluations.count, topRejectReason: topRejectReason)
            reportGenerationFailure(
                provider: kind,
                category: .qualityGate,
                qualityGateReason: rejectedCandidate?.qualityGateReason,
                latencyBucket: rejectedCandidate?.responseLatencyBucket
            )
            return
        }
        let shapedSchedule = bestCandidate.shapedSchedule
        guard shapedSchedule.isEmpty == false else {
            reportGenerationFailure(
                provider: kind,
                category: .qualityGate,
                qualityGateReason: bestCandidate.qualityGateReason,
                latencyBucket: bestCandidate.responseLatencyBucket
            )
            return
        }

        let result = await aiPlaybackQueue.submitWindow(
            schedule: shapedSchedule,
            routing: practiceSession.settingsProvider.soundRoutingSettings,
            submittedAtUptimeSeconds: now,
            provider: kind,
            requestGeneration: phraseGenerationAtRequest
        )
        guard result.wasAccepted else {
            reportGenerationDiscard(provider: kind, outcome: .stalePlayback)
            return
        }
        if let outcome = staleGenerationOutcome(
            activationAtRequest: activationAtRequest,
            phraseGenerationAtRequest: phraseGenerationAtRequest,
            kind: kind
        ) {
            reportGenerationDiscard(provider: kind, outcome: outcome)
            return
        }
        latestSchedule = result.shiftedSchedule
        latestCandidateDiagnostics = CandidateDiagnostics(
            band: bestCandidate.assessment.band,
            candidateCount: evaluations.count,
            topRejectReason: topRejectReason
        )
        lastImprovStatusText = makeStatusText(decision: decision, noteSnapshot: noteSnapshot)
        notifyStateChanged()
    }

    private func generateCreativeResponses(
        backend: any ImprovBackendProtocol,
        kind: ImprovBackendKind,
        phrase: CreativeDuetPhrase,
        requestPolicy: DuetPhrasePolicy.RequestPolicy,
        baseSeed: UInt64,
        requestID: Int,
        activationID: Int
    ) async throws -> [CreativeDuetResponse] {
        let candidateCount = preferredCandidateCount(for: kind)
        var responses: [CreativeDuetResponse] = []
        responses.reserveCapacity(candidateCount)

        for candidateIndex in 0 ..< candidateCount {
            let generation = makeCreativeDuetGeneration(
                requestPolicy: requestPolicy,
                requestID: requestID,
                activationID: activationID,
                seed: candidateSeed(baseSeed: baseSeed, candidateIndex: candidateIndex)
            )
            let startedAt = nowUptimeSeconds()
            let response = try await backend.generateCreativeResponse(
                phrase: phrase,
                generation: generation,
                timeout: backendTimeout
            )
            guard response.provider == kind, response.generation == generation else {
                throw ImprovBackendClientError.invalidResponse
            }
            responses.append(applyingObservedLatency(to: response, startedAt: startedAt))
        }

        return responses
    }

    private func preferredCandidateCount(for kind: ImprovBackendKind) -> Int {
        switch kind {
        case .localRule:
            3
        case .networkBonjourHTTPAriaV2, .networkBonjourWebSocketAriaV2, .localCoreMLDuet:
            1
        }
    }

    private func makeCreativeDuetGeneration(
        requestPolicy: DuetPhrasePolicy.RequestPolicy,
        requestID: Int,
        activationID: Int,
        seed: UInt64
    ) -> CreativeDuetGeneration {
        CreativeDuetGeneration(
            requestID: requestID,
            activationID: activationID,
            seed: seed,
            sessionID: improvSessionID,
            parameters: ImprovGenerateParams(
                topP: 0.95,
                maxTokens: max(1, requestPolicy.maxTokens),
                strategy: "continuous",
                seed: seed
            )
        )
    }

    private func candidateSeed(baseSeed: UInt64, candidateIndex: Int) -> UInt64 {
        guard candidateIndex > 0 else { return baseSeed }
        return baseSeed &+ (UInt64(candidateIndex) &* 0x9E37_79B9_7F4A_7C15)
    }

    private func evaluateCandidate(
        response: CreativeDuetResponse,
        noteSnapshot: DuetPhraseBuffer.Snapshot,
        controlMode: DuetTurnTakingCore.Mode,
        horizonSeconds: TimeInterval
    ) -> CandidateEvaluation {
        let rawAssessment = DuetPhrasePolicy.assessSchedule(
            response.schedule,
            noteSnapshot: noteSnapshot,
            horizonSeconds: horizonSeconds
        )
        let shapedSchedule = DuetPhrasePolicy.shapeSchedule(
            response.schedule,
            noteSnapshot: noteSnapshot,
            controlMode: controlMode,
            horizonSeconds: horizonSeconds
        )
        let responseLatencySeconds = responseLatencySeconds(for: response)
        let responseQualityAssessment = ImprovQualityRubric().assess(
            shapedSchedule,
            responseLatencySeconds: responseLatencySeconds,
            context: ImprovQualityRubric.phraseContext(from: noteSnapshot)
        )
        let assessment: DuetPhrasePolicy.QualityAssessment = if shapedSchedule.isEmpty {
            rawAssessment.band == .reject
                ? rawAssessment
                : .init(
                    band: .reject,
                    score: rawAssessment.score,
                    reasons: rawAssessment.reasons.isEmpty ? [.fragmentedWindow] : rawAssessment.reasons,
                    noteOnCount: rawAssessment.noteOnCount,
                    effectiveDurationSeconds: rawAssessment.effectiveDurationSeconds
                )
        } else {
            DuetPhrasePolicy.assessSchedule(
                shapedSchedule,
                noteSnapshot: noteSnapshot,
                horizonSeconds: horizonSeconds
            )
        }
        return CandidateEvaluation(
            shapedSchedule: shapedSchedule,
            assessment: assessment,
            responseQualityAssessment: responseQualityAssessment,
            responseLatencyBucket: responseLatencySeconds.map { .init(seconds: $0) }
        )
    }

    private func selectBestCandidate(from evaluations: [CandidateEvaluation]) -> CandidateEvaluation? {
        evaluations
            .filter {
                $0.shapedSchedule.isEmpty == false
                    && $0.assessment.band != .reject
                    && $0.responseQualityAssessment.isUsable
            }
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

    private func responseLatencySeconds(for response: CreativeDuetResponse) -> TimeInterval? {
        switch response.provenance {
        case let .backendGenerated(latencyMS):
            latencyMS.map { TimeInterval($0) / 1_000 }
        }
    }

    private func applyingObservedLatency(
        to response: CreativeDuetResponse,
        startedAt: TimeInterval
    ) -> CreativeDuetResponse {
        let elapsedSeconds = nowUptimeSeconds() - startedAt
        guard elapsedSeconds.isFinite else { return response }
        let observedLatencyMS = Int((max(0, elapsedSeconds) * 1_000).rounded(.awayFromZero))

        switch response.provenance {
        case let .backendGenerated(latencyMS):
            return CreativeDuetResponse(
                schedule: response.schedule,
                provider: response.provider,
                generation: response.generation,
                provenance: .backendGenerated(latencyMS: max(latencyMS ?? 0, observedLatencyMS))
            )
        }
    }

    private func bandRank(_ band: DuetPhrasePolicy.QualityAssessment.Band) -> Int {
        switch band {
        case .acceptable:
            2
        case .risky:
            1
        case .reject:
            0
        }
    }

    @discardableResult
    private func syncBackendDiscoveryIfNeeded() -> Bool {
        guard let kind = selectedBackendKind() else {
            if lastKnownBackendKind != nil, isEnabled {
                let invalidatedPhraseGeneration = invalidateGeneration()
                Task { [aiPlaybackQueue] in
                    await aiPlaybackQueue.stopAll(rejectingThrough: invalidatedPhraseGeneration)
                }
                discoveryOrchestrator.stopAll()
                lastKnownBackendKind = nil
            }
            reportGenerationFailure(provider: nil, category: .invalidSelection)
            return false
        }
        guard kind != lastKnownBackendKind else { return true }
        if lastKnownBackendKind != nil, isEnabled {
            let invalidatedPhraseGeneration = invalidateGeneration()
            Task { [aiPlaybackQueue] in
                await aiPlaybackQueue.stopAll(rejectingThrough: invalidatedPhraseGeneration)
            }
        }
        lastKnownBackendKind = kind
        discoveryOrchestrator.start(for: kind)
        return true
    }

    private func failureCategory(for error: any Error) -> GenerationFailureCategory {
        if error is ImprovBackendRegistryError {
            return .unavailable
        }
        if let error = error as? LocalRuleImprovBackendError {
            return error == .timeout ? .timeout : .invalidResponse
        }
        if let error = error as? LocalCoreMLDuetImprovBackendError {
            return error == .timeout ? .timeout : .invalidResponse
        }
        if let error = error as? AriaNetworkBonjourHTTPImprovBackendError {
            switch error {
            case .backendNotResolved, .discoveryDenied, .discoveryFailed:
                return .unavailable
            case .emptyReply:
                return .invalidResponse
            }
        }
        if let error = error as? AriaNetworkBonjourWebSocketImprovBackendError {
            switch error {
            case .backendNotResolved, .discoveryDenied, .discoveryFailed:
                return .unavailable
            case .missingWebSocketPath, .invalidWebSocketURL, .emptyReply:
                return .invalidResponse
            }
        }
        if let error = error as? ImprovStreamingClientError {
            return error == .timeout ? .timeout : .invalidResponse
        }
        if error is ImprovBackendClientError {
            return .invalidResponse
        }
        if let error = error as? URLError, error.code == .timedOut {
            return .timeout
        }
        return .failed
    }

    private func reportGenerationFailure(
        provider: ImprovBackendKind?,
        category: GenerationFailureCategory,
        qualityGateReason: String? = nil,
        latencyBucket: PianoPerformanceDurationBucket? = nil
    ) {
        let providerToken = provider?.rawValue ?? "none"
        let statusText = "AI 即兴：\(category.statusText)（\(providerToken)）"
        guard generationFailureStatusText != statusText else { return }
        let reason = if category == .qualityGate {
            [
                "provider=\(providerToken)",
                "failure=\(category.rawValue)",
                "quality=\(qualityGateReason ?? "unknown")",
                "latency=\(latencyBucket?.rawValue ?? "none")",
            ].joined(separator: ";")
        } else {
            "provider=\(providerToken);failure=\(category.rawValue)"
        }

        diagnosticsReporter?.recordSystem(
            severity: .warning,
            category: .ai,
            stage: "continuousDuet.generate",
            summary: "AI 即兴生成失败",
            reason: reason
        )
        generationFailureStatusText = statusText
        lastImprovStatusText = statusText
        notifyStateChanged()
    }

    private func staleGenerationOutcome(
        activationAtRequest: Int,
        phraseGenerationAtRequest: Int,
        kind: ImprovBackendKind
    ) -> GenerationDiscardOutcome? {
        guard isEnabled else { return .staleDisabled }
        guard activationAtRequest == activationID else { return .staleActivation }
        guard phraseGenerationAtRequest == phraseGeneration else { return .stalePhrase }
        guard selectedBackendKind() == kind else { return .staleBackend }
        return nil
    }

    private func reportGenerationDiscard(
        provider: ImprovBackendKind,
        outcome: GenerationDiscardOutcome
    ) {
        diagnosticsReporter?.recordSystem(
            severity: .info,
            category: .ai,
            stage: "continuousDuet.discard",
            summary: "AI 即兴响应已丢弃",
            reason: "provider=\(provider.rawValue);outcome=\(outcome.rawValue)"
        )
    }

    @discardableResult
    private func invalidateGeneration() -> Int {
        activationID &+= 1
        let invalidatedPhraseGeneration = invalidatePhraseGeneration()
        latestCandidateDiagnostics = nil
        notifyStateChanged()
        return invalidatedPhraseGeneration
    }

    @discardableResult
    private func invalidatePhraseGeneration() -> Int {
        phraseGeneration &+= 1
        for task in inFlightGenerateTasks.values {
            task.cancel()
        }
        inFlightGenerateTasks.removeAll(keepingCapacity: true)
        lastWindowRequestTimestampSeconds = nil
        isGenerating = false
        return phraseGeneration
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
