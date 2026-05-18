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

        practiceInputEventsTask = Task { [weak self] in
            for await event in practiceInputEventSource.events {
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

        guard isPracticeInputRunning == false else { return }

        practiceInputGeneration += 1
        practiceInputActiveSinceUptimeSeconds = ProcessInfo.processInfo.systemUptime
        audioStepAttemptAccumulator.setMode(.midiInput)
        audioStepAttemptAccumulator.resetForNewStep(generation: practiceInputGeneration)

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
        practiceInputGeneration += 1
        audioStepAttemptAccumulator.resetForNewStep(generation: practiceInputGeneration)
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

        guard case let .noteOn(note, velocity) = event.kind, velocity > 0 else { return }

        let detected = DetectedNoteEvent(
            midiNote: note,
            confidence: 1.0,
            onsetScore: 1.0,
            isOnset: true,
            timestamp: event.receivedAt,
            generation: practiceInputGeneration,
            source: .bluetoothMIDI
        )

        let expectedMIDINotes = uniqueMIDINotes(in: currentStep)
        let wrongMIDINotes = Set(makeWrongCandidateMIDINotesForPracticeInput(expectedMIDINotes))

        audioStepAttemptAccumulator.register(event: detected)
        let matchResult: StepAttemptMatchResult
        if isHandSeparatedStepMatchingEnabled {
            let expectedByHand = uniqueMIDINotesByHand(in: currentStep)
            matchResult = audioStepAttemptAccumulator.evaluateHandSeparated(
                expectedRightMIDINotes: expectedByHand.right,
                expectedLeftMIDINotes: expectedByHand.left,
                wrongCandidateMIDINotes: wrongMIDINotes,
                generation: practiceInputGeneration,
                at: detected.timestamp,
                handGateBoost: handGateState.isNearKeyboard || handGateState.hasDownwardMotion
            )
        } else {
            matchResult = audioStepAttemptAccumulator.evaluate(
                expectedMIDINotes: expectedMIDINotes,
                wrongCandidateMIDINotes: wrongMIDINotes,
                generation: practiceInputGeneration,
                at: detected.timestamp,
                handGateBoost: handGateState.isNearKeyboard || handGateState.hasDownwardMotion
            )
        }

        switch matchResult {
            case .matched:
                Self.practiceInputLogger.info(
                    "midi matched step=\(self.currentStepIndex, privacy: .public) expected=\(expectedMIDINotes, privacy: .public) noteOn=\(note, privacy: .public) vel=\(velocity, privacy: .public)"
                )
                audioStepAttemptAccumulator.markMatchedAndRequireRearm(
                    expectedMIDINotes: expectedMIDINotes,
                    at: detected.timestamp
                )
                advanceToNextStep()
            case let .wrong(reason):
                debugLogPracticeInputProgressIfNeeded(
                    kind: "wrong",
                    detail: reason,
                    note: note,
                    velocity: velocity,
                    expectedMIDINotes: expectedMIDINotes,
                    receivedAtUptimeSeconds: event.receivedAtUptimeSeconds
                )
            case let .insufficient(progress):
                debugLogPracticeInputProgressIfNeeded(
                    kind: "insufficient",
                    detail: progress,
                    note: note,
                    velocity: velocity,
                    expectedMIDINotes: expectedMIDINotes,
                    receivedAtUptimeSeconds: event.receivedAtUptimeSeconds
                )
        }
    }

    private func debugLogPracticeInputProgressIfNeeded(
        kind: String,
        detail: String,
        note: Int,
        velocity: Int,
        expectedMIDINotes: [Int],
        receivedAtUptimeSeconds: TimeInterval
    ) {
        // Rate-limit + de-dup to avoid flooding logs when the user repeats key presses.
        if receivedAtUptimeSeconds - practiceInputDebugLastLoggedAtUptimeSeconds < 0.25 {
            return
        }

        let message = "midi \(kind) step=\(currentStepIndex) expected=\(expectedMIDINotes) noteOn=\(note) vel=\(velocity) detail=\(detail)"
        if message == practiceInputDebugLastMessage {
            return
        }

        practiceInputDebugLastLoggedAtUptimeSeconds = receivedAtUptimeSeconds
        practiceInputDebugLastMessage = message
        Self.practiceInputLogger.info("\(message, privacy: .public)")
    }

    private func makeWrongCandidateMIDINotesForPracticeInput(_ expectedMIDINotes: [Int]) -> [Int] {
        var result: Set<Int> = []
        for note in expectedMIDINotes {
            result.insert(note - 2)
            result.insert(note - 1)
            result.insert(note + 1)
            result.insert(note + 2)
        }
        result.subtract(expectedMIDINotes)
        return result.sorted()
    }
}
