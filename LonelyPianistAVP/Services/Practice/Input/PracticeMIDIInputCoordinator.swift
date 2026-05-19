import Foundation
import os

@MainActor
final class PracticeMIDIInputCoordinator: PracticeMIDIInputCoordinating, PracticeSessionLifecycleProtocol {
    struct Snapshot: Equatable {
        var practiceState: PracticeSessionState
        var autoplayState: PracticeSessionAutoplayState
        var isManualReplayPlaying: Bool
        var currentStepIndex: Int
        var expectedNotes: [PracticeStepNote]
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "PracticeMIDIInputCoordinator"
    )

    private let practiceInputEventSource: PracticeInputEventSourceProtocol?
    private let matcher: MIDIPracticeStepMatcher
    private let stateStore: PracticeSessionStateStore
    private weak var effectHandler: (any PracticeSessionEffectHandling)?

    private var midi1EventsTask: Task<Void, Never>?
    private var midi2EventsTask: Task<Void, Never>?
    private var hasShutdown = false

    init(
        practiceInputEventSource: PracticeInputEventSourceProtocol?,
        matcher: MIDIPracticeStepMatcher,
        stateStore: PracticeSessionStateStore,
        effectHandler: any PracticeSessionEffectHandling,
        consumeEvents: Bool
    ) {
        self.practiceInputEventSource = practiceInputEventSource
        self.matcher = matcher
        self.stateStore = stateStore
        self.effectHandler = effectHandler
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
    }

    func refreshForCurrentState() {
        guard let snapshot = latestSnapshot else {
            stop()
            return
        }
        refresh(for: snapshot)
    }

    func stop() {
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
            matcher.reset(
                stepIndex: snapshot.currentStepIndex,
                expectedNotes: snapshot.expectedNotes,
                configuredAt: .now
            )
            stateStore.practiceInputLastResetStepIndex = snapshot.currentStepIndex
        }

        guard stateStore.isPracticeInputRunning == false else { return }
        do {
            try practiceInputEventSource.start()
            stateStore.isPracticeInputRunning = true
        } catch {
            stateStore.isPracticeInputRunning = false
            resetMatchingStateIfNeeded()
            logger.error("practice input start failed: \(error.localizedDescription, privacy: .public)")
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
        guard stateStore.practiceInputActiveSinceUptimeSeconds != nil ||
            stateStore.practiceInputLastResetStepIndex != nil ||
            stateStore.isPracticeInputRunning
        else {
            return
        }
        stateStore.practiceInputActiveSinceUptimeSeconds = nil
        stateStore.practiceInputLastResetStepIndex = nil
        stateStore.practiceInputGeneration += 1
        matcher.reset(stepIndex: -1, expectedNotes: [], configuredAt: .now)
    }

    private func handleMIDI1(_ event: MIDI1InputEvent) {
        guard stateStore.isPracticeInputRunning else { return }
        guard let snapshot = latestSnapshot else { return }
        guard snapshot.autoplayState == .off else { return }
        guard snapshot.isManualReplayPlaying == false else { return }
        guard case .guiding = snapshot.practiceState else { return }
        guard snapshot.expectedNotes.isEmpty == false else { return }

        if let since = stateStore.practiceInputActiveSinceUptimeSeconds, event.receivedAtUptimeSeconds < since {
            return
        }

        switch event.kind {
        case let .noteOn(note, _):
            let matchResult = matcher.registerNoteOn(note: note, at: event.receivedAt)
            if case .matched = matchResult {
                effectHandler?.handle(effect: .advanceToNextStep)
            }
        case let .noteOff(note, _):
            matcher.registerNoteOff(note: note, at: event.receivedAt)
        default:
            break
        }
    }

    private func handleMIDI2(_ event: MIDI2InputEvent) {
        guard stateStore.isPracticeInputRunning else { return }
        guard let snapshot = latestSnapshot else { return }
        guard snapshot.autoplayState == .off else { return }
        guard snapshot.isManualReplayPlaying == false else { return }
        guard case .guiding = snapshot.practiceState else { return }
        guard snapshot.expectedNotes.isEmpty == false else { return }

        if let since = stateStore.practiceInputActiveSinceUptimeSeconds, event.receivedAtUptimeSeconds < since {
            return
        }

        switch event.kind {
        case let .noteOn(note, _):
            let matchResult = matcher.registerNoteOn(note: note, at: event.receivedAt)
            if case .matched = matchResult {
                effectHandler?.handle(effect: .advanceToNextStep)
            }
        case let .noteOff(note, _):
            matcher.registerNoteOff(note: note, at: event.receivedAt)
        default:
            break
        }
    }
}
