import Foundation

@MainActor
final class PracticeMIDIInputService: PerformanceObservationStreamProviding {
    struct Snapshot: Equatable {
        var practiceState: PracticeSessionState
        var autoplayState: PracticeSessionAutoplayState
        var isManualReplayPlaying: Bool
        var currentStepIndex: Int
        var expectedNotes: [PracticeStepNote]
    }

    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let practiceInputEventSource: PracticeInputEventSourceProtocol?
    private let matcher: any MIDIPracticeStepMatchingProtocol
    private let stateStore: PracticeSessionStateStore
    private let observationRecorder: PracticeSessionRecorder?
    private weak var effectHandler: (any PracticeSessionEffectHandlerProtocol)?
    private let observationBroadcaster = AsyncStreamBroadcaster<PerformanceObservation>()

    private var midi1EventsTask: Task<Void, Never>?
    private var midi2EventsTask: Task<Void, Never>?
    private var observationAdapter = MIDIPerformanceObservationAdapter()
    private var observationRecordingTask: Task<Void, Never>?
    private var activeSourceGeneration: UInt64?
    private var hasShutdown = false

    init(
        practiceInputEventSource: PracticeInputEventSourceProtocol?,
        matcher: any MIDIPracticeStepMatchingProtocol,
        stateStore: PracticeSessionStateStore,
        effectHandler: any PracticeSessionEffectHandlerProtocol,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        observationRecorder: PracticeSessionRecorder? = nil,
        consumeEvents: Bool
    ) {
        self.practiceInputEventSource = practiceInputEventSource
        self.matcher = matcher
        self.stateStore = stateStore
        self.observationRecorder = observationRecorder
        self.effectHandler = effectHandler
        self.diagnosticsReporter = diagnosticsReporter
        if consumeEvents { bindStreamsIfNeeded() }
    }

    func shutdown() {
        guard hasShutdown == false else { return }
        hasShutdown = true
        stop()
        midi1EventsTask?.cancel()
        midi1EventsTask = nil
        midi2EventsTask?.cancel()
        midi2EventsTask = nil
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
        activeSourceGeneration = nil
        guard let practiceInputEventSource else { return }
        stopSourceIfNeeded(practiceInputEventSource)
        resetMatchingStateIfNeeded()
    }

    private var latestSnapshot: Snapshot?

    func refresh(for snapshot: Snapshot) {
        latestSnapshot = snapshot
        guard let practiceInputEventSource else { return }

        guard snapshot.autoplayState == .off, snapshot.isManualReplayPlaying == false else {
            stop()
            return
        }

        guard case .guiding = snapshot.practiceState, snapshot.expectedNotes.isEmpty == false else {
            stop()
            return
        }

        if stateStore.practiceInputLastResetStepIndex != snapshot.currentStepIndex {
            stateStore.practiceInputGeneration += 1
            stateStore.practiceInputActiveSinceUptimeSeconds = ProcessInfo.processInfo.systemUptime
            activeSourceGeneration = UInt64(max(0, stateStore.practiceInputGeneration))
            matcher.reset(
                stepIndex: snapshot.currentStepIndex,
                expectedNotes: snapshot.expectedNotes
            )
            stateStore.practiceInputLastResetStepIndex = snapshot.currentStepIndex
        }

        if stateStore.isPracticeInputRunning {
            effectHandler?.handle(effect: .inputCapabilitiesAvailable(.midi))
            return
        }
        do {
            try practiceInputEventSource.start()
            stateStore.isPracticeInputRunning = true
            activeSourceGeneration = UInt64(max(0, stateStore.practiceInputGeneration))
            effectHandler?.handle(effect: .inputCapabilitiesAvailable(.midi))
        } catch {
            stateStore.isPracticeInputRunning = false
            resetMatchingStateIfNeeded()
            diagnosticsReporter?.recordSystem(
                severity: .error,
                category: .midi,
                stage: "practiceInput.start",
                summary: "练习 MIDI 输入启动失败",
                reason: error.localizedDescription
            )
        }
    }

    private func bindStreamsIfNeeded() {
        guard let practiceInputEventSource else { return }
        guard midi1EventsTask == nil, midi2EventsTask == nil else { return }

        let midi1Stream = practiceInputEventSource.midi1EventsStream()
        midi1EventsTask = Task { [weak self] in
            for await event in midi1Stream {
                await MainActor.run {
                    self?.handleMIDI1(event)
                }
            }
        }

        let midi2Stream = practiceInputEventSource.midi2EventsStream()
        midi2EventsTask = Task { [weak self] in
            for await event in midi2Stream {
                await MainActor.run {
                    self?.handleMIDI2(event)
                }
            }
        }
    }

    private func stopSourceIfNeeded(_ practiceInputEventSource: PracticeInputEventSourceProtocol) {
        guard stateStore.isPracticeInputRunning else { return }
        practiceInputEventSource.stop()
        stateStore.isPracticeInputRunning = false
    }

    private func resetMatchingStateIfNeeded() {
        activeSourceGeneration = nil
        guard stateStore.practiceInputActiveSinceUptimeSeconds != nil ||
            stateStore.practiceInputLastResetStepIndex != nil ||
            stateStore.isPracticeInputRunning
        else {
            return
        }
        stateStore.practiceInputActiveSinceUptimeSeconds = nil
        stateStore.practiceInputLastResetStepIndex = nil
        stateStore.practiceInputGeneration += 1
        observationAdapter.resetClockCalibration()
        matcher.reset(stepIndex: -1, expectedNotes: [])
    }

    var capabilities: PerformanceInputCapabilities {
        .midi
    }

    func performanceObservationsStream() -> AsyncStream<PerformanceObservation> {
        observationBroadcaster.makeStream(bufferingPolicy: .bufferingNewest(4096))
    }

    func waitForPendingObservationRecording() async {
        await observationRecordingTask?.value
    }

    private func handleMIDI1(_ event: MIDI1InputEvent) {
        guard let generation = acceptedGeneration(for: event.receivedAtUptimeSeconds) else { return }
        let observation = observationAdapter.observation(for: event, generation: generation)
        publish(observation)
        handle(observation)
    }

    private func handleMIDI2(_ event: MIDI2InputEvent) {
        guard let generation = acceptedGeneration(for: event.receivedAtUptimeSeconds) else { return }
        let observation = observationAdapter.observation(for: event, generation: generation)
        publish(observation)
        handle(observation)
    }

    private func acceptedGeneration(for hostUptimeSeconds: TimeInterval) -> UInt64? {
        guard let activeSourceGeneration,
              stateStore.isPracticeInputRunning,
              let activeSince = stateStore.practiceInputActiveSinceUptimeSeconds,
              hostUptimeSeconds >= activeSince
        else {
            return nil
        }
        return activeSourceGeneration
    }

    private func publish(_ observation: PerformanceObservation) {
        observationBroadcaster.yield(observation)
        guard let observationRecorder else { return }
        let previousTask = observationRecordingTask
        observationRecordingTask = Task {
            await previousTask?.value
            await observationRecorder.record(observation)
        }
    }

    private func handle(_ observation: PerformanceObservation) {
        guard stateStore.isPracticeInputRunning else { return }
        guard let snapshot = latestSnapshot else { return }
        guard snapshot.autoplayState == .off else { return }
        guard snapshot.isManualReplayPlaying == false else { return }
        guard case .guiding = snapshot.practiceState else { return }
        guard snapshot.expectedNotes.isEmpty == false else { return }

        if let since = stateStore.practiceInputActiveSinceUptimeSeconds,
           observation.timing.host.seconds < since
        {
            return
        }

        switch observation.event {
        case .noteOn:
            guard let matchResult = matcher.register(observation) else { return }
            effectHandler?.handle(effect: .attemptEvaluated(matchResult))
            if matchResult.isMatched {
                effectHandler?.handle(effect: .advanceToNextStep)
            }
        case .noteOff:
            _ = matcher.register(observation)
        case let .controller(.controlChange(controller, _)) where controller == 120 || controller == 123:
            resetMatcherAfterInputDiscontinuity()
        default:
            break
        }
    }

    private func resetMatcherAfterInputDiscontinuity() {
        guard let snapshot = latestSnapshot else { return }
        matcher.reset(
            stepIndex: snapshot.currentStepIndex,
            expectedNotes: snapshot.expectedNotes
        )
        stateStore.practiceInputGeneration += 1
        stateStore.practiceInputActiveSinceUptimeSeconds = ProcessInfo.processInfo.systemUptime
        activeSourceGeneration = UInt64(max(0, stateStore.practiceInputGeneration))
        observationAdapter.resetClockCalibration()
        diagnosticsReporter?.recordSystem(
            severity: .warning,
            category: .midi,
            stage: "practiceInput.discontinuity",
            summary: "MIDI 输入中断后已重置匹配器",
            reason: "stream buffer overflow"
        )
    }
}
