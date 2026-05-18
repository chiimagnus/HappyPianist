import Foundation
import os

extension PracticeSessionViewModel {
    private static let practiceInputLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "PracticeInput-StepAdvance"
    )

    func bindPracticeInputStreamsIfNeeded() {
        guard let practiceInputEventSource else { return }
        guard practiceInputEventsTask == nil else { return }

        // Create the stream eagerly so the broadcaster registers this subscriber immediately.
        // This avoids dropping early events that might arrive before the consumer task starts running.
        let stream = practiceInputEventSource.eventsStream()
        practiceInputEventsTask = Task { [weak self] in
            for await event in stream {
                await MainActor.run {
                    self?.handlePracticeInputEvent(event)
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
            practiceInputActiveSinceUptimeSeconds = nil
            decisionLogger.error("practice input start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopPracticeInput() {
        guard let practiceInputEventSource else { return }
        guard isPracticeInputRunning else { return }

        practiceInputEventSource.stop()
        isPracticeInputRunning = false
        practiceInputActiveSinceUptimeSeconds = nil
        practiceInputLastResetStepIndex = nil
        practiceInputGeneration += 1
        midiPracticeStepMatcher.reset(stepIndex: -1, expectedNotes: [], configuredAt: .now)
    }

    private func handlePracticeInputEvent(_ event: PracticeInputEvent) {
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
            guard velocity > 0 else { return }

            let expectedMIDINotes = uniqueMIDINotes(in: currentStep)
            let matchResult = midiPracticeStepMatcher.registerNoteOn(note: note, at: event.receivedAt)

            switch matchResult {
            case .matched:
                Self.practiceInputLogger.info(
                    "midi matched id=\(event.debugEventID ?? 0, privacy: .public) step=\(self.currentStepIndex, privacy: .public) expected=\(expectedMIDINotes, privacy: .public) noteOn=\(note, privacy: .public) vel=\(velocity, privacy: .public)"
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
        receivedAtUptimeSeconds: TimeInterval
    ) {
        // Rate-limit + de-dup to avoid flooding logs when the user repeats key presses.
        if receivedAtUptimeSeconds - practiceInputDebugLastLoggedAtUptimeSeconds < 0.25 {
            return
        }

        let message = "midi \(kind) id=\(eventID ?? 0) step=\(currentStepIndex) expected=\(expectedMIDINotes) noteOn=\(note) vel=\(velocity) detail=\(detail)"
        if message == practiceInputDebugLastMessage {
            return
        }

        practiceInputDebugLastLoggedAtUptimeSeconds = receivedAtUptimeSeconds
        practiceInputDebugLastMessage = message
        Self.practiceInputLogger.info("\(message, privacy: .public)")
    }

}
