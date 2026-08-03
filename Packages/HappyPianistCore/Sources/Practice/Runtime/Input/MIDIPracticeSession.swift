import Diagnostics
import Foundation
import MIDI

/// Shared, host-agnostic MIDI practice input lifecycle.
@MainActor
public final class MIDIPracticeSession {
    public struct Configuration: Equatable, Sendable {
        public let acceptsInput: Bool
        public let currentStepIndex: Int
        public let expectedNotes: [PracticeStepNote]

        public init(
            acceptsInput: Bool,
            currentStepIndex: Int,
            expectedNotes: [PracticeStepNote]
        ) {
            self.acceptsInput = acceptsInput
            self.currentStepIndex = currentStepIndex
            self.expectedNotes = expectedNotes
        }
    }

    public enum Event: Sendable {
        case inputRunning(Bool)
        case inputCapabilitiesAvailable(PerformanceInputCapabilities)
        case attemptEvaluated(StepAttemptMatchResult)
        case advanceToNextStep
        case inputDiscontinuity
    }

    /// Host-owned effects needed to finish a MIDI practice session without
    /// coupling the shared input lifecycle to a specific UI or persistence implementation.
    public struct Termination {
        fileprivate let resetOutput: @MainActor () async -> Void
        fileprivate let flushInputEffects: @MainActor () async -> Bool
        fileprivate let flushProgress: @MainActor () async -> Bool

        public init(
            resetOutput: @escaping @MainActor () async -> Void,
            flushProgress: @escaping @MainActor () async -> Bool,
            flushInputEffects: @escaping @MainActor () async -> Bool = { true }
        ) {
            self.resetOutput = resetOutput
            self.flushInputEffects = flushInputEffects
            self.flushProgress = flushProgress
        }
    }

    private let inputEventSource: (any MIDIInputEventSource)?
    private let matcher: any MIDIPracticeStepMatchingProtocol
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let observationRecorder: PracticeSessionRecorder?
    private let onObservation: (@MainActor (PerformanceObservation) -> Void)?

    private var eventContinuations: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var observationContinuations: [UUID: AsyncStream<PerformanceObservation>.Continuation] = [:]
    private var midi1EventsTask: Task<Void, Never>?
    private var midi2EventsTask: Task<Void, Never>?
    private var observationRecordingTask: Task<Void, Never>?
    private var observationAdapter = MIDIPerformanceObservationAdapter()
    private var configuration: Configuration?
    private var activeSourceGeneration: UInt64?
    private var activeSinceUptimeSeconds: TimeInterval?
    private var lastMatcherConfiguration: Configuration?
    private var isInputRunning = false
    private var hasShutdown = false

    public init(
        inputEventSource: (any MIDIInputEventSource)?,
        matcher: any MIDIPracticeStepMatchingProtocol = MIDIPracticeStepMatcher(),
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        observationRecorder: PracticeSessionRecorder? = nil,
        onObservation: (@MainActor (PerformanceObservation) -> Void)? = nil,
        consumeEvents: Bool = true
    ) {
        self.inputEventSource = inputEventSource
        self.matcher = matcher
        self.diagnosticsReporter = diagnosticsReporter
        self.observationRecorder = observationRecorder
        self.onObservation = onObservation
        if consumeEvents { bindStreamsIfNeeded() }
    }

    deinit {
        midi1EventsTask?.cancel()
        midi2EventsTask?.cancel()
        observationRecordingTask?.cancel()
    }

    public var capabilities: PerformanceInputCapabilities { .midi }

    public func events() -> AsyncStream<Event> {
        let identifier = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            eventContinuations[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.eventContinuations.removeValue(forKey: identifier)
                }
            }
        }
    }

    public func performanceObservations() -> AsyncStream<PerformanceObservation> {
        let identifier = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(4096)) { continuation in
            observationContinuations[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.observationContinuations.removeValue(forKey: identifier)
                }
            }
        }
    }

    public func update(configuration: Configuration) {
        self.configuration = configuration
        guard configuration.acceptsInput, configuration.expectedNotes.isEmpty == false else {
            stop()
            return
        }
        guard let inputEventSource else { return }

        if lastMatcherConfiguration != configuration {
            resetMatcher(
                stepIndex: configuration.currentStepIndex,
                expectedNotes: configuration.expectedNotes
            )
        }

        guard isInputRunning == false else {
            emit(.inputCapabilitiesAvailable(.midi))
            return
        }

        do {
            try inputEventSource.start()
            isInputRunning = true
            activeSourceGeneration = UInt64(max(0, generation))
            emit(.inputRunning(true))
            emit(.inputCapabilitiesAvailable(.midi))
        } catch {
            resetMatchingState()
            diagnosticsReporter?.recordSystem(
                severity: .error,
                category: .midi,
                stage: "practiceInput.start",
                summary: "练习 MIDI 输入启动失败",
                reason: String(describing: type(of: error))
            )
        }
    }

    public func stop() {
        activeSourceGeneration = nil
        if isInputRunning, let inputEventSource {
            inputEventSource.stop()
        }
        let wasRunning = isInputRunning
        isInputRunning = false
        resetMatchingState()
        if wasRunning { emit(.inputRunning(false)) }
    }

    public func shutdown() {
        guard hasShutdown == false else { return }
        hasShutdown = true
        stop()
        finishStreams()
    }

    /// Stops accepting input before output reset, drains accepted observations,
    /// then lets the host persist input-derived effects and approved facts. A
    /// failed flush leaves the session resumable rather than silently discarding data.
    @discardableResult
    public func finish(termination: Termination) async -> Bool {
        guard hasShutdown == false else { return true }
        stop()
        await termination.resetOutput()
        await waitForPendingObservationRecording()
        guard await termination.flushInputEffects() else { return false }
        guard await termination.flushProgress() else { return false }
        hasShutdown = true
        finishStreams()
        return true
    }

    private func finishStreams() {
        midi1EventsTask?.cancel()
        midi1EventsTask = nil
        midi2EventsTask?.cancel()
        midi2EventsTask = nil
        eventContinuations.values.forEach { $0.finish() }
        observationContinuations.values.forEach { $0.finish() }
        eventContinuations = [:]
        observationContinuations = [:]
    }

    public func waitForPendingObservationRecording() async {
        await observationRecordingTask?.value
    }

    private var generation = 0

    private func bindStreamsIfNeeded() {
        guard let inputEventSource else { return }
        let midi1Stream = inputEventSource.midi1EventsStream()
        midi1EventsTask = Task { [weak self] in
            for await event in midi1Stream {
                self?.handleMIDI1(event)
            }
        }
        let midi2Stream = inputEventSource.midi2EventsStream()
        midi2EventsTask = Task { [weak self] in
            for await event in midi2Stream {
                self?.handleMIDI2(event)
            }
        }
    }

    private func resetMatcher(stepIndex: Int, expectedNotes: [PracticeStepNote]) {
        generation &+= 1
        activeSinceUptimeSeconds = ProcessInfo.processInfo.systemUptime
        activeSourceGeneration = UInt64(max(0, generation))
        matcher.reset(stepIndex: stepIndex, expectedNotes: expectedNotes)
        lastMatcherConfiguration = configuration
    }

    private func resetMatchingState() {
        guard activeSinceUptimeSeconds != nil || lastMatcherConfiguration != nil || isInputRunning else { return }
        activeSinceUptimeSeconds = nil
        lastMatcherConfiguration = nil
        generation &+= 1
        observationAdapter.resetClockCalibration()
        matcher.reset(stepIndex: -1, expectedNotes: [])
    }

    private func handleMIDI1(_ event: MIDI1InputEvent) {
        guard let generation = acceptedGeneration(for: event.receivedAtUptimeSeconds) else { return }
        handle(observationAdapter.observation(for: event, generation: generation))
    }

    private func handleMIDI2(_ event: MIDI2InputEvent) {
        guard let generation = acceptedGeneration(for: event.receivedAtUptimeSeconds) else { return }
        handle(observationAdapter.observation(for: event, generation: generation))
    }

    private func acceptedGeneration(for hostUptimeSeconds: TimeInterval) -> UInt64? {
        guard let activeSourceGeneration,
              isInputRunning,
              let activeSinceUptimeSeconds,
              hostUptimeSeconds >= activeSinceUptimeSeconds
        else { return nil }
        return activeSourceGeneration
    }

    private func handle(_ observation: PerformanceObservation) {
        observationContinuations.values.forEach { $0.yield(observation) }
        onObservation?(observation)
        if let observationRecorder {
            let previousTask = observationRecordingTask
            observationRecordingTask = Task {
                await previousTask?.value
                await observationRecorder.record(observation)
            }
        }

        guard isInputRunning,
              let configuration,
              configuration.acceptsInput,
              configuration.expectedNotes.isEmpty == false
        else { return }

        switch observation.event {
        case .noteOn:
            guard let matchResult = matcher.register(observation) else { return }
            emit(.attemptEvaluated(matchResult))
            if matchResult.isMatched { emit(.advanceToNextStep) }
        case .noteOff:
            _ = matcher.register(observation)
        case let .controller(.controlChange(controller, _)) where controller == 120 || controller == 123:
            resetMatcher(stepIndex: configuration.currentStepIndex, expectedNotes: configuration.expectedNotes)
            observationAdapter.resetClockCalibration()
            emit(.inputDiscontinuity)
            diagnosticsReporter?.recordSystem(
                severity: .warning,
                category: .midi,
                stage: "practiceInput.discontinuity",
                summary: "MIDI 输入中断后已重置匹配器",
                reason: "stream buffer overflow"
            )
        default:
            break
        }
    }

    private func emit(_ event: Event) {
        eventContinuations.values.forEach { $0.yield(event) }
    }
}
