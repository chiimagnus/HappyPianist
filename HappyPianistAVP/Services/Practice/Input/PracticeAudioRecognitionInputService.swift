import Foundation

@MainActor
final class PracticeAudioRecognitionInputService: PerformanceObservationStreamProviding {
    struct Snapshot: Equatable {
        var practiceState: PracticeSessionState
        var autoplayState: PracticeSessionAutoplayState
        var isManualReplayPlaying: Bool
        var expectedMIDINotes: [Int]
        var wrongCandidateMIDINotes: [Int]
        var handGateBoost: Bool
        var suppressUntil: Date?
    }

    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let service: PracticeAudioRecognitionServiceProtocol?
    private let accumulator: AudioStepAttemptAccumulator
    private let stateStore: PracticeSessionStateStore
    private let observationRecorder: PracticeSessionRecorder?
    private weak var effectHandler: (any PracticeSessionEffectHandlerProtocol)?
    private let observationBroadcaster = AsyncStreamBroadcaster<PerformanceObservation>()

    private var hasShutdown = false
    private var startTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var observationRecordingTask: Task<Void, Never>?

    init(
        service: PracticeAudioRecognitionServiceProtocol?,
        accumulator: AudioStepAttemptAccumulator,
        stateStore: PracticeSessionStateStore,
        effectHandler: any PracticeSessionEffectHandlerProtocol,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        observationRecorder: PracticeSessionRecorder? = nil,
        consumeStreams: Bool
    ) {
        self.service = service
        self.accumulator = accumulator
        self.stateStore = stateStore
        self.observationRecorder = observationRecorder
        self.effectHandler = effectHandler
        self.diagnosticsReporter = diagnosticsReporter
        if consumeStreams { bindStreamsIfNeeded() }
    }

    func shutdown() {
        guard hasShutdown == false else { return }
        hasShutdown = true
        stop()
        eventsTask?.cancel()
        eventsTask = nil
        statusTask?.cancel()
        statusTask = nil
        observationBroadcaster.finish()
    }

    func refreshForCurrentState() {
        guard let snapshot = latestSnapshot else {
            stop()
            return
        }
        refresh(for: snapshot)
    }

    func stop() {
        guard let service else { return }
        startTask?.cancel()
        startTask = nil
        stateStore.audioRecognitionGeneration += 1
        accumulator.resetForNewStep(generation: stateStore.audioRecognitionGeneration)
        service.stop()
        stateStore.isAudioRecognitionRunning = false
        stateStore.audioRecognitionStatus = .stopped
    }

    private var latestSnapshot: Snapshot?

    func refresh(for snapshot: Snapshot) {
        guard hasShutdown == false else { return }
        latestSnapshot = snapshot
        guard let service else { return }

        guard snapshot.autoplayState == .off else {
            stop()
            return
        }
        guard snapshot.isManualReplayPlaying == false else {
            stop()
            return
        }
        guard case .guiding = snapshot.practiceState, snapshot.expectedMIDINotes.isEmpty == false else {
            stop()
            return
        }

        accumulator.setMode(.lowLatency)
        stateStore.audioRecognitionGeneration += 1
        accumulator.resetForNewStep(generation: stateStore.audioRecognitionGeneration)

        if stateStore.isAudioRecognitionRunning {
            service.updateExpectedNotes(
                snapshot.expectedMIDINotes,
                wrongCandidateMIDINotes: snapshot.wrongCandidateMIDINotes,
                generation: stateStore.audioRecognitionGeneration
            )
            applyPendingSuppressIfNeeded(generation: stateStore.audioRecognitionGeneration)
            return
        }

        stateStore.isAudioRecognitionRunning = true
        let startGeneration = stateStore.audioRecognitionGeneration
        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await service.start(
                    expectedMIDINotes: snapshot.expectedMIDINotes,
                    wrongCandidateMIDINotes: snapshot.wrongCandidateMIDINotes,
                    generation: startGeneration,
                    suppressUntil: snapshot.suppressUntil
                )
                guard stateStore.audioRecognitionGeneration == startGeneration else {
                    service.stop()
                    stateStore.isAudioRecognitionRunning = false
                    startTask = nil
                    guard hasShutdown == false else { return }
                    refreshForCurrentState()
                    return
                }
                startTask = nil
                applyPendingSuppressIfNeeded(generation: startGeneration)
            } catch {
                startTask = nil
                guard hasShutdown == false,
                      stateStore.audioRecognitionGeneration == startGeneration
                else { return }
                stateStore.isAudioRecognitionRunning = false
                recordError(error)
                diagnosticsReporter?.recordSystem(
                    severity: .error,
                    category: .audio,
                    stage: "practiceRecognition.start",
                    summary: "练习音频识别启动失败",
                    reason: error.localizedDescription
                )
            }
        }
    }

    private func bindStreamsIfNeeded() {
        guard let service else { return }
        guard eventsTask == nil else { return }

        eventsTask = Task { [weak self] in
            for await evidence in service.targetEvidence {
                await MainActor.run {
                    self?.handle(evidence)
                }
            }
        }

        statusTask = Task { [weak self] in
            for await status in service.statusUpdates {
                await MainActor.run {
                    self?.stateStore.audioRecognitionStatus = status
                    if case .permissionDenied = status {
                        self?.stateStore.audioRecognitionErrorMessage = "未授予麦克风权限"
                    }
                    if case let .engineFailed(reason) = status {
                        self?.stateStore.audioRecognitionErrorMessage = reason
                    }
                }
            }
        }
    }

    private func applyPendingSuppressIfNeeded(generation: Int) {
        guard let service else { return }
        guard let suppressUntil = stateStore.audioRecognitionSuppressUntil else { return }
        guard suppressUntil > .now else { return }
        service.suppressRecognition(until: suppressUntil, generation: generation)
    }

    private func recordError(_ error: Error) {
        guard stateStore.audioRecognitionErrorMessage == nil else { return }
        stateStore.audioRecognitionErrorMessage = String(describing: error)
    }

    var capabilities: PerformanceInputCapabilities {
        .targetAudio
    }

    func performanceObservationsStream() -> AsyncStream<PerformanceObservation> {
        observationBroadcaster.makeStream(bufferingPolicy: .bufferingNewest(4096))
    }

    private func handle(_ evidence: TargetAudioEvidence) {
        guard let snapshot = latestSnapshot else { return }
        guard snapshot.autoplayState == .off else { return }
        guard snapshot.isManualReplayPlaying == false else { return }
        guard evidence.generation == stateStore.audioRecognitionGeneration else { return }
        publishObservation(for: evidence)
        guard evidence.result != .unknown else {
            effectHandler?.handle(effect: .attemptEvaluated(.insufficientEvidence))
            return
        }

        accumulator.register(evidence: evidence)
        let wrongCandidates = Set(snapshot.wrongCandidateMIDINotes)
        let matchResult = accumulator.evaluate(
            expectedMIDINotes: snapshot.expectedMIDINotes,
            wrongCandidateMIDINotes: wrongCandidates,
            generation: stateStore.audioRecognitionGeneration,
            at: evidence.timestamp,
            handGateBoost: snapshot.handGateBoost
        )

        effectHandler?.handle(effect: .attemptEvaluated(matchResult))
        if matchResult.isMatched {
            accumulator.markMatchedAndRequireRearm(
                expectedMIDINotes: snapshot.expectedMIDINotes,
                at: evidence.timestamp
            )
            effectHandler?.handle(effect: .advanceToNextStep)
        }
    }

    private func publishObservation(for evidence: TargetAudioEvidence) {
        let host = evidence.timestamp
        let observation = PerformanceObservation(
            source: .init(
                kind: .targetAudio,
                id: "microphone-targeted-harmonic-template",
                generation: UInt64(max(0, evidence.generation))
            ),
            timing: PerformanceClockReading(
                host: host,
                source: nil,
                correctedHost: host,
                mapping: nil,
                provenance: .hostOnly
            ),
            event: .targetAudioDetection(
                targetMIDINotes: evidence.targetMIDINotes,
                detectedMIDINotes: evidence.targetConfidenceByMIDINote.keys.sorted(),
                result: evidence.result.observationResult
            ),
            confidence: evidence.confidence
        )
        observationBroadcaster.yield(observation)
        guard let observationRecorder else { return }
        let previousTask = observationRecordingTask
        observationRecordingTask = Task {
            await previousTask?.value
            await observationRecorder.record(observation)
        }
    }
}

private extension TargetAudioEvidence.Result {
    var observationResult: PerformanceObservation.TargetAudioDetectionResult {
        switch self {
        case .detected: .detected
        case .contradicted: .contradicted
        case .mixed: .mixed
        case .unknown: .unknown
        }
    }
}
