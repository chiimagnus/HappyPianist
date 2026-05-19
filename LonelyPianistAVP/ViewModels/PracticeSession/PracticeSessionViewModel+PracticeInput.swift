import Foundation
import os

extension PracticeSessionViewModel {
    private static let practiceInputLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "PracticeInput-StepAdvance"
    )

    func bindPracticeInputStreamsIfNeeded() {
        guard let practiceInputEventSource else { return }
        guard practiceInputMIDI1EventsTask == nil, practiceInputMIDI2EventsTask == nil else { return }

        let midi1Stream = practiceInputEventSource.midi1EventsStream()
        practiceInputMIDI1EventsTask = Task { [weak self] in
            for await event in midi1Stream {
                await MainActor.run {
                    self?.handleMIDI1PracticeInputEvent(event)
                }
            }
        }

        let midi2Stream = practiceInputEventSource.midi2EventsStream()
        practiceInputMIDI2EventsTask = Task { [weak self] in
            for await event in midi2Stream {
                await MainActor.run {
                    self?.handleMIDI2PracticeInputEvent(event)
                }
            }
        }
    }

    func refreshPracticeInputForCurrentState() {
        guard let practiceInputEventSource else { return }

        guard autoplayState == .off, isManualReplayPlaying == false else {
            stopPracticeInput()
            return
        }

        guard case .guiding = state, currentStep != nil else {
            stopPracticeInput()
            return
        }

        if practiceInputLastResetStepIndex != currentStepIndex {
            practiceInputGeneration += 1
            practiceInputActiveSinceUptimeSeconds = ProcessInfo.processInfo.systemUptime
            midiPracticeStepMatcher.reset(
                stepIndex: currentStepIndex,
                expectedNotes: currentStep?.notes ?? [],
                configuredAt: Date()
            )
            practiceInputLastResetStepIndex = currentStepIndex
        }

        guard isPracticeInputRunning == false else { return }

        do {
            try practiceInputEventSource.start()
            isPracticeInputRunning = true
        } catch {
            isPracticeInputRunning = false
            resetPracticeInputMatchingState()
            decisionLogger.error("practice input start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopPracticeInput() {
        guard let practiceInputEventSource else { return }
        stopPracticeInputSourceIfNeeded(practiceInputEventSource)
        resetPracticeInputMatchingState()
    }

    private func stopPracticeInputSourceIfNeeded(_ practiceInputEventSource: PracticeInputEventSourceProtocol) {
        guard isPracticeInputRunning else { return }
        practiceInputEventSource.stop()
        isPracticeInputRunning = false
    }

    private func resetPracticeInputMatchingState() {
        practiceInputActiveSinceUptimeSeconds = nil
        practiceInputLastResetStepIndex = nil
        practiceInputGeneration += 1
        midiPracticeStepMatcher.reset(stepIndex: -1, expectedNotes: [], configuredAt: .now)
    }

    private func handleMIDI1PracticeInputEvent(_ event: MIDI1InputEvent) {
        guard isPracticeInputRunning else { return }
        guard autoplayState == .off else { return }
        guard isManualReplayPlaying == false else { return }
        guard case .guiding = state else { return }
        guard let currentStep else { return }

        if let since = practiceInputActiveSinceUptimeSeconds, event.receivedAtUptimeSeconds < since {
            return
        }

        switch event.kind {
        case let .noteOn(note, velocity):
            let expectedMIDINotes = uniqueMIDINotes(in: currentStep)
            let matchResult = midiPracticeStepMatcher.registerNoteOn(note: note, at: event.receivedAt)

            switch matchResult {
            case .matched:
                logPerNoteIfEnabled(
                    "midi1 matched id=\(event.debugEventID ?? 0) step=\(currentStepIndex) src=\(describe(event.source)) expected=\(expectedMIDINotes) noteOn=\(note) vel=\(velocity)"
                )
                advanceToNextStep()
            case let .wrong(reason):
                debugLogPracticeInputProgressIfNeeded(
                    kind: "wrong",
                    detail: reason,
                    note: note,
                    velocity: velocity,
                    expectedMIDINotes: expectedMIDINotes,
                    eventID: event.debugEventID,
                    source: describe(event.source),
                    receivedAtUptimeSeconds: event.receivedAtUptimeSeconds
                )
            case let .insufficient(progress):
                debugLogPracticeInputProgressIfNeeded(
                    kind: "insufficient",
                    detail: progress,
                    note: note,
                    velocity: velocity,
                    expectedMIDINotes: expectedMIDINotes,
                    eventID: event.debugEventID,
                    source: describe(event.source),
                    receivedAtUptimeSeconds: event.receivedAtUptimeSeconds
                )
            }
        case let .noteOff(note, _):
            midiPracticeStepMatcher.registerNoteOff(note: note, at: event.receivedAt)
            return
        default:
            return
        }
    }

    private func handleMIDI2PracticeInputEvent(_ event: MIDI2InputEvent) {
        guard isPracticeInputRunning else { return }
        guard autoplayState == .off else { return }
        guard isManualReplayPlaying == false else { return }
        guard case .guiding = state else { return }
        guard let currentStep else { return }

        if let since = practiceInputActiveSinceUptimeSeconds, event.receivedAtUptimeSeconds < since {
            return
        }

        switch event.kind {
        case let .noteOn(note, velocity16):
            let expectedMIDINotes = uniqueMIDINotes(in: currentStep)
            let matchResult = midiPracticeStepMatcher.registerNoteOn(note: note, at: event.receivedAt)

            switch matchResult {
            case .matched:
                logPerNoteIfEnabled(
                    "midi2 matched id=\(event.debugEventID ?? 0) step=\(currentStepIndex) src=\(describe(event.source)) expected=\(expectedMIDINotes) noteOn=\(note) vel16=\(Int(velocity16))"
                )
                advanceToNextStep()
            case let .wrong(reason):
                debugLogPracticeInputProgressIfNeeded(
                    kind: "wrong",
                    detail: reason,
                    note: note,
                    velocity: Int(velocity16),
                    expectedMIDINotes: expectedMIDINotes,
                    eventID: event.debugEventID,
                    source: describe(event.source),
                    receivedAtUptimeSeconds: event.receivedAtUptimeSeconds
                )
            case let .insufficient(progress):
                debugLogPracticeInputProgressIfNeeded(
                    kind: "insufficient",
                    detail: progress,
                    note: note,
                    velocity: Int(velocity16),
                    expectedMIDINotes: expectedMIDINotes,
                    eventID: event.debugEventID,
                    source: describe(event.source),
                    receivedAtUptimeSeconds: event.receivedAtUptimeSeconds
                )
            }
        case let .noteOff(note, _):
            midiPracticeStepMatcher.registerNoteOff(note: note, at: event.receivedAt)
            return
        default:
            return
        }
    }

    private func debugLogPracticeInputProgressIfNeeded(
        kind: String,
        detail: String,
        note: Int,
        velocity: Int,
        expectedMIDINotes: [Int],
        eventID: Int64?,
        source: String?,
        receivedAtUptimeSeconds: TimeInterval
    ) {
        // Rate-limit + de-dup to avoid flooding logs when the user repeats key presses.
        guard isPerNoteDiagnosticsEnabled else { return }
        if receivedAtUptimeSeconds - practiceInputDebugLastLoggedAtUptimeSeconds < 0.25 {
            return
        }

        let sourceToken = source.map { " src=\($0)" } ?? ""
        let message = "midi \(kind) id=\(eventID ?? 0) step=\(currentStepIndex)\(sourceToken) expected=\(expectedMIDINotes) noteOn=\(note) vel=\(velocity) detail=\(detail)"
        if message == practiceInputDebugLastMessage {
            return
        }

        practiceInputDebugLastLoggedAtUptimeSeconds = receivedAtUptimeSeconds
        practiceInputDebugLastMessage = message
        logPerNoteIfEnabled(message)
    }

    private var isPerNoteDiagnosticsEnabled: Bool {
        let config = MIDIDiagnosticsConfiguration.live()
        return config.isPerNoteInfoLoggingEnabled || config.isPerNoteDebugLoggingEnabled
    }

    private func logPerNoteIfEnabled(_ message: String) {
        let config = MIDIDiagnosticsConfiguration.live()
        if config.isPerNoteInfoLoggingEnabled {
            Self.practiceInputLogger.info("\(message, privacy: .public)")
            return
        }
        if config.isPerNoteDebugLoggingEnabled {
            Self.practiceInputLogger.debug("\(message, privacy: .public)")
        }
    }

    private func describe(_ source: MIDI1InputEvent.Source) -> String {
        switch source.identifier {
        case let .endpointUniqueID(uniqueID):
            if let name = source.endpointName, name.isEmpty == false {
                return "uid=\(uniqueID)(\(name))"
            }
            return "uid=\(uniqueID)"
        case let .sourceIndex(index):
            if let name = source.endpointName, name.isEmpty == false {
                return "idx=\(index)(\(name))"
            }
            return "idx=\(index)"
        }
    }

    private func describe(_ source: MIDI2InputEvent.Source) -> String {
        switch source.identifier {
        case let .endpointUniqueID(uniqueID):
            if let name = source.endpointName, name.isEmpty == false {
                return "uid=\(uniqueID)(\(name))"
            }
            return "uid=\(uniqueID)"
        case let .sourceIndex(index):
            if let name = source.endpointName, name.isEmpty == false {
                return "idx=\(index)(\(name))"
            }
            return "idx=\(index)"
        }
    }

}
