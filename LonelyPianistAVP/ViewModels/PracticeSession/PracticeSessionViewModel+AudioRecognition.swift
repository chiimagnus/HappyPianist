import Foundation
import os

extension PracticeSessionViewModel {
    func refreshAudioRecognitionForCurrentState() {
        guard let audioRecognitionService else { return }
        guard isPracticeAudioRecognitionEnabled else {
            stopAudioRecognition()
            return
        }
        guard autoplayState == .off else {
            stopAudioRecognition()
            return
        }
        guard isManualReplayPlaying == false else {
            stopAudioRecognition()
            return
        }
        guard case .guiding = state, let currentStep else {
            stopAudioRecognition()
            return
        }

        let expectedMIDINotes = uniqueMIDINotes(in: currentStep)
        let wrongMIDINotes = makeWrongCandidateMIDINotes(expectedMIDINotes)
        audioRecognitionService.configureDetectorMode(
            practiceAudioRecognitionDetectorModeSnapshot,
            profile: harmonicTemplateTuningProfileSnapshot
        )
        audioStepAttemptAccumulator.setMode(.lowLatency)
        audioRecognitionGeneration += 1
        audioStepAttemptAccumulator.resetForNewStep(generation: audioRecognitionGeneration)

        if isAudioRecognitionRunning {
            audioRecognitionService.updateExpectedNotes(
                expectedMIDINotes,
                wrongCandidateMIDINotes: wrongMIDINotes,
                generation: audioRecognitionGeneration
            )
            applyPendingAudioRecognitionSuppressIfNeeded(generation: audioRecognitionGeneration)
            decisionLogger.debug("audio generation update=\(self.audioRecognitionGeneration, privacy: .public)")
            return
        }

        isAudioRecognitionRunning = true
        let startGeneration = audioRecognitionGeneration
        let startExpectedMIDINotes = expectedMIDINotes
        let startWrongMIDINotes = wrongMIDINotes
        let startSuppressUntil = audioRecognitionSuppressUntil.flatMap { $0 > Date() ? $0 : nil }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await audioRecognitionService.start(
                    expectedMIDINotes: startExpectedMIDINotes,
                    wrongCandidateMIDINotes: startWrongMIDINotes,
                    generation: startGeneration,
                    suppressUntil: startSuppressUntil
                )
                guard audioRecognitionGeneration == startGeneration,
                      autoplayState == .off,
                      isPracticeAudioRecognitionEnabled,
                      case .guiding = state
                else {
                    stopAudioRecognition()
                    return
                }
                applyPendingAudioRecognitionSuppressIfNeeded(generation: startGeneration)
                decisionLogger.info("audio service started generation=\(startGeneration, privacy: .public)")
            } catch {
                isAudioRecognitionRunning = false
                decisionLogger.error("audio service failed start generation=\(startGeneration, privacy: .public)")
                recordAudioRecognitionError(error)
            }
        }
    }

    func refreshAudioRecognitionFromSettings() {
        practiceAudioRecognitionDetectorModeSnapshot = Self.readPracticeAudioRecognitionDetectorMode()
        harmonicTemplateTuningProfileSnapshot = Self.profile(for: practiceAudioRecognitionDetectorModeSnapshot)
        audioRecognitionService?.configureDetectorMode(
            practiceAudioRecognitionDetectorModeSnapshot,
            profile: harmonicTemplateTuningProfileSnapshot
        )
        refreshAudioRecognitionForCurrentState()
    }

    func stopAudioRecognition() {
        guard let audioRecognitionService else { return }
        let wasRunning = isAudioRecognitionRunning
        audioRecognitionGeneration += 1
        audioStepAttemptAccumulator.resetForNewStep(generation: audioRecognitionGeneration)
        audioRecognitionService.stop()
        isAudioRecognitionRunning = false
        audioRecognitionStatus = .stopped
        if wasRunning {
            decisionLogger.debug("audio service stopped")
        }
    }

    @discardableResult
    func prepareAudioRecognitionSuppressWindowForPlayback() -> Date {
        let suppressUntil = Date().addingTimeInterval(audioRecognitionSuppressDuration)
        audioRecognitionSuppressUntil = suppressUntil
        audioRecognitionService?.suppressRecognition(
            until: suppressUntil,
            generation: audioRecognitionGeneration
        )
        return suppressUntil
    }

    func bindAudioRecognitionStreamsIfNeeded() {
        guard let audioRecognitionService else { return }
        guard audioRecognitionEventsTask == nil else { return }

        audioRecognitionEventsTask = Task { [weak self] in
            for await event in audioRecognitionService.events {
                await MainActor.run {
                    self?.handleAudioRecognitionEvent(event)
                }
            }
        }

        audioRecognitionStatusTask = Task { [weak self] in
            for await status in audioRecognitionService.statusUpdates {
                await MainActor.run {
                    self?.audioRecognitionStatus = status
                    if case .permissionDenied = status {
                        self?.audioRecognitionErrorMessage = "未授予麦克风权限"
                    }
                    if case let .engineFailed(reason) = status {
                        self?.audioRecognitionErrorMessage = reason
                    }
                }
            }
        }

        audioRecognitionDebugTask = Task { [weak self] in
            for await snapshot in audioRecognitionService.debugSnapshots {
                await MainActor.run {
                    self?.audioRecognitionDebugSnapshot = snapshot
                }
            }
        }
    }

    private func recordAudioRecognitionError(_ error: Error) {
        guard audioRecognitionErrorMessage == nil else { return }
        audioRecognitionErrorMessage = audioErrorText(for: error)
    }

    private func applyPendingAudioRecognitionSuppressIfNeeded(generation: Int) {
        guard let audioRecognitionService else { return }
        guard let audioRecognitionSuppressUntil else { return }
        guard audioRecognitionSuppressUntil > Date() else { return }
        audioRecognitionService.suppressRecognition(
            until: audioRecognitionSuppressUntil,
            generation: generation
        )
    }

    private func handleAudioRecognitionEvent(_ event: DetectedNoteEvent) {
        guard isPracticeAudioRecognitionEnabled else { return }
        guard autoplayState == .off else { return }
        guard isManualReplayPlaying == false else { return }
        guard event.generation == audioRecognitionGeneration else { return }
        if let audioRecognitionSuppressUntil, event.timestamp <= audioRecognitionSuppressUntil {
            decisionLogger.debug("audio event suppressed generation=\(event.generation, privacy: .public)")
            return
        }
        guard let currentStep else { return }

        let expectedMIDINotes = uniqueMIDINotes(in: currentStep)
        let wrongMIDINotes = Set(makeWrongCandidateMIDINotes(expectedMIDINotes))

        audioStepAttemptAccumulator.register(event: event)
        let matchResult = audioStepAttemptAccumulator.evaluate(
            expectedMIDINotes: expectedMIDINotes,
            wrongCandidateMIDINotes: wrongMIDINotes,
            generation: audioRecognitionGeneration,
            at: event.timestamp,
            handGateBoost: handGateState.isNearKeyboard || handGateState.hasDownwardMotion
        )

        switch matchResult {
            case .matched:
                audioStepAttemptAccumulator.markMatchedAndRequireRearm(
                    expectedMIDINotes: expectedMIDINotes,
                    at: event.timestamp
                )
                setFeedback(.correct)
                advanceToNextStep()
                decisionLogger.debug("audio matched advanced generation=\(event.generation, privacy: .public)")
            case .wrong:
                setFeedback(.wrong)
                decisionLogger.debug("audio wrong feedback generation=\(event.generation, privacy: .public)")
            case .insufficient:
                break
        }
    }

    private func makeWrongCandidateMIDINotes(_ expectedMIDINotes: [Int]) -> [Int] {
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

    private var isPracticeAudioRecognitionEnabled: Bool {
        audioRecognitionEnabledSnapshot
    }

    var audioRecognitionGenerationForTesting: Int {
        audioRecognitionGeneration
    }

    var audioRecognitionSuppressRemainingSeconds: TimeInterval {
        guard let audioRecognitionSuppressUntil else { return 0 }
        return max(0, audioRecognitionSuppressUntil.timeIntervalSinceNow)
    }

    private static func readPracticeAudioRecognitionDetectorMode() -> PracticeAudioRecognitionDetectorMode {
        if let rawValue = UserDefaults.standard.string(forKey: "practiceStep3AudioRecognitionMode"),
           let mode = PracticeAudioRecognitionDetectorMode(rawValue: rawValue)
        {
            return mode
        }
        return .harmonicTemplate
    }

    private static func profile(for _: PracticeAudioRecognitionDetectorMode) -> HarmonicTemplateTuningProfile {
        .lowLatencyDefault
    }
}
