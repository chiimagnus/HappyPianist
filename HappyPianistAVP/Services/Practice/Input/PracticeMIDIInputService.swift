import Diagnostics
import Foundation
import MIDI
import Practice

/// AVP presentation adapter for the shared MIDI-only practice lifecycle.
@MainActor
final class PracticeMIDIInputService: PerformanceObservationStreamProviding {
    struct Snapshot: Equatable {
        var practiceState: PracticeSessionState
        var autoplayState: PracticeSessionAutoplayState
        var isManualReplayPlaying: Bool
        var currentStepIndex: Int
        var expectedNotes: [PracticeStepNote]
    }

    private let stateStore: PracticeSessionHostState
    private weak var effectHandler: (any PracticeSessionEffectHandlerProtocol)?
    private let midiSession: MIDIPracticeSession
    private var eventTask: Task<Void, Never>?
    private var hasShutdown = false

    init(
        practiceInputEventSource: (any MIDIInputEventSource)?,
        matcher: any MIDIPracticeStepMatchingProtocol,
        stateStore: PracticeSessionHostState,
        effectHandler: any PracticeSessionEffectHandlerProtocol,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        observationRecorder: PracticeSessionRecorder? = nil,
        consumeEvents: Bool
    ) {
        self.stateStore = stateStore
        self.effectHandler = effectHandler
        midiSession = MIDIPracticeSession(
            inputEventSource: practiceInputEventSource,
            matcher: matcher,
            diagnosticsReporter: diagnosticsReporter,
            observationRecorder: observationRecorder,
            consumeEvents: consumeEvents
        )
        bindEvents()
    }

    func shutdown() {
        guard hasShutdown == false else { return }
        hasShutdown = true
        eventTask?.cancel()
        eventTask = nil
        midiSession.shutdown()
    }

    @discardableResult
    func finish(termination: MIDIPracticeSession.Termination) async -> Bool {
        guard hasShutdown == false else { return true }
        guard await midiSession.finish(termination: termination) else { return false }
        hasShutdown = true
        eventTask?.cancel()
        eventTask = nil
        return true
    }

    func refreshForCurrentState() {
        guard let snapshot = latestSnapshot else {
            stop()
            return
        }
        refresh(for: snapshot)
    }

    func stop() {
        midiSession.stop()
    }

    private var latestSnapshot: Snapshot?

    func refresh(for snapshot: Snapshot) {
        latestSnapshot = snapshot
        let isGuiding: Bool
        if case .guiding = snapshot.practiceState {
            isGuiding = true
        } else {
            isGuiding = false
        }
        midiSession.update(configuration: MIDIPracticeSession.Configuration(
            acceptsInput: snapshot.autoplayState == .off
                && snapshot.isManualReplayPlaying == false
                && isGuiding,
            currentStepIndex: snapshot.currentStepIndex,
            expectedNotes: snapshot.expectedNotes
        ))
    }

    var capabilities: PerformanceInputCapabilities {
        midiSession.capabilities
    }

    func performanceObservationsStream() -> AsyncStream<PerformanceObservation> {
        midiSession.performanceObservations()
    }

    func waitForPendingObservationRecording() async {
        await midiSession.waitForPendingObservationRecording()
    }

    private func bindEvents() {
        let events = midiSession.events()
        eventTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: MIDIPracticeSession.Event) {
        switch event {
        case let .inputRunning(isRunning):
            stateStore.isPracticeInputRunning = isRunning
        case let .inputCapabilitiesAvailable(capabilities):
            effectHandler?.handle(effect: .inputCapabilitiesAvailable(capabilities))
        case let .attemptEvaluated(result):
            effectHandler?.handle(effect: .attemptEvaluated(result))
        case .advanceToNextStep:
            effectHandler?.handle(effect: .advanceToNextStep)
        case .inputDiscontinuity:
            break
        }
    }
}
